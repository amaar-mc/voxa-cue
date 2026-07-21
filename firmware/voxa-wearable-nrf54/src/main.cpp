#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/time_units.h>

#include <cstddef>
#include <cstdint>

#include "voxa_ble_transport.hpp"
#include "voxa_driver_health.hpp"
#include "voxa_drv2605l.hpp"
#include "voxa_patterns.hpp"
#include "voxa_protocol.hpp"
#include "voxa_session_light.hpp"

namespace {

constexpr std::uint32_t kDriverProbeIntervalMilliseconds = 250U;
constexpr std::uint8_t kSessionLightPwmSteps = 32U;
constexpr std::uint32_t kSessionLightPwmStepMicroseconds = 250U;
constexpr std::uint32_t kSessionLightHeartbeatTimeoutMilliseconds = 5000U;
constexpr std::uint32_t kMainLoopSleepMicroseconds = 100U;
constexpr std::uint32_t kBleInitializationRetryMilliseconds = 250U;

const struct gpio_dt_spec redOutput =
    GPIO_DT_SPEC_GET(DT_ALIAS(voxa_red), gpios);
const struct gpio_dt_spec blueOutput =
    GPIO_DT_SPEC_GET(DT_ALIAS(voxa_blue), gpios);
const struct gpio_dt_spec greenOutput =
    GPIO_DT_SPEC_GET(DT_ALIAS(voxa_green), gpios);
const struct gpio_dt_spec buzzerOutput =
    GPIO_DT_SPEC_GET(DT_ALIAS(voxa_buzzer), gpios);

struct PlaybackState {
  bool active;
  bool waitingForRepeat;
  voxa::CommandPacket command;
  voxa::PatternProgram program;
  std::size_t segmentIndex;
  std::uint8_t repeatsRemaining;
  std::uint32_t segmentDeadlineMilliseconds;
  std::uint32_t lastDriverProbeMilliseconds;
};

struct SessionLightState {
  voxa::SessionLightCommand command;
  bool hasCommand;
  std::uint32_t modeStartedMilliseconds;
  std::uint32_t lastHeartbeatMilliseconds;
  std::uint32_t nextPwmStepMicroseconds;
  std::uint8_t pwmPhase;
};

enum class PlaybackUpdate : std::uint8_t {
  kNone = 0U,
  kCompleted = 1U,
  kDriverFault = 2U,
};

PlaybackState playback{};
SessionLightState sessionLight{};
voxa::EmergencyBuzzerState emergencyBuzzer{};
voxa::SequenceTracker sequenceTracker{};
voxa::DriverHealthState driverHealth{};

bool timeReached(std::uint32_t now, std::uint32_t deadline) {
  return static_cast<std::int32_t>(now - deadline) >= 0;
}

bool configureOutput(const struct gpio_dt_spec& output) {
  return gpio_is_ready_dt(&output) &&
         gpio_pin_configure_dt(&output, GPIO_OUTPUT_INACTIVE) == 0;
}

void writeOutput(const struct gpio_dt_spec& output, bool enabled) {
  if (!gpio_is_ready_dt(&output)) {
    return;
  }
#if defined(VOXA_RGB_COMMON_ANODE)
  const int rawValue = enabled ? 0 : 1;
#else
  const int rawValue = enabled ? 1 : 0;
#endif
  (void)gpio_pin_set_raw(output.port, output.pin, rawValue);
}

void writeBuzzer(bool enabled) {
  if (gpio_is_ready_dt(&buzzerOutput)) {
    (void)gpio_pin_set_raw(buzzerOutput.port, buzzerOutput.pin,
                           enabled ? 1 : 0);
  }
}

void initializeSessionOutputs() {
  (void)configureOutput(redOutput);
  (void)configureOutput(blueOutput);
  (void)configureOutput(greenOutput);
  (void)configureOutput(buzzerOutput);
  writeOutput(redOutput, false);
  writeOutput(greenOutput, false);
  writeOutput(blueOutput, false);
  writeBuzzer(false);

  voxa::resetEmergencyBuzzerState(&emergencyBuzzer);
  sessionLight.command = voxa::SessionLightCommand{
      voxa::kProtocolVersion, voxa::SessionLightMode::kOff, 0U};
  sessionLight.nextPwmStepMicroseconds =
      k_ticks_to_us_floor32(k_uptime_ticks());
}

bool sessionLightIsCurrent(std::uint32_t nowMilliseconds) {
  return sessionLight.hasCommand &&
         voxa::ble_transport::isCentralConnected() &&
         nowMilliseconds - sessionLight.lastHeartbeatMilliseconds <=
             kSessionLightHeartbeatTimeoutMilliseconds;
}

std::uint8_t pwmDutySteps(std::uint8_t channel) {
  return static_cast<std::uint8_t>(
      (static_cast<std::uint16_t>(channel) * kSessionLightPwmSteps + 127U) /
      255U);
}

voxa::RgbColor currentSessionLightColor(std::uint32_t nowMilliseconds) {
  if (!sessionLightIsCurrent(nowMilliseconds)) {
    return voxa::RgbColor{0U, 0U, 0U};
  }
  return voxa::resolvedSessionColor(
      sessionLight.command,
      nowMilliseconds - sessionLight.modeStartedMilliseconds);
}

void updateEmergencyBuzzerOutput(std::uint32_t nowMilliseconds) {
  if (!sessionLightIsCurrent(nowMilliseconds)) {
    voxa::silenceEmergencyBuzzerState(&emergencyBuzzer);
    writeBuzzer(false);
    return;
  }

  const bool sounding = voxa::updateEmergencyBuzzerState(
      sessionLight.command.mode, nowMilliseconds, &emergencyBuzzer);
  writeBuzzer(sounding);
}

void updateSessionLightOutput(std::uint32_t nowMilliseconds,
                              std::uint32_t nowMicroseconds) {
  if (!timeReached(nowMicroseconds, sessionLight.nextPwmStepMicroseconds)) {
    return;
  }

  const std::uint32_t overdueMicroseconds =
      nowMicroseconds - sessionLight.nextPwmStepMicroseconds;
  const std::uint32_t elapsedSteps =
      overdueMicroseconds / kSessionLightPwmStepMicroseconds + 1U;
  sessionLight.nextPwmStepMicroseconds +=
      elapsedSteps * kSessionLightPwmStepMicroseconds;
  sessionLight.pwmPhase = static_cast<std::uint8_t>(
      (sessionLight.pwmPhase + elapsedSteps) % kSessionLightPwmSteps);

  const voxa::RgbColor color = currentSessionLightColor(nowMilliseconds);
  writeOutput(redOutput,
              sessionLight.pwmPhase < pwmDutySteps(color.red));
  writeOutput(greenOutput,
              sessionLight.pwmPhase < pwmDutySteps(color.green));
  writeOutput(blueOutput,
              sessionLight.pwmPhase < pwmDutySteps(color.blue));
}

void handleSessionLightFrame(
    const voxa::ble_transport::ReceivedSessionLightFrame& frame,
    std::uint32_t nowMilliseconds) {
  const voxa::ParseSessionLightResult parsed =
      voxa::parseSessionLight(frame.bytes, frame.reportedLength);
  if (!parsed.valid) {
    return;
  }

  if (!sessionLight.hasCommand ||
      sessionLight.command.mode != parsed.command.mode) {
    sessionLight.modeStartedMilliseconds = nowMilliseconds;
  }
  sessionLight.command = parsed.command;
  sessionLight.hasCommand = true;
  sessionLight.lastHeartbeatMilliseconds = nowMilliseconds;
}

bool setHapticOutput(std::uint8_t amplitudePercent,
                     voxa::Intensity intensity) {
  const std::uint8_t amplitude =
      voxa::scaledAmplitudeForIntensity(intensity, amplitudePercent);
  return voxa::drv2605l::setRealtimeValue(amplitude);
}

bool publishStatus(std::uint16_t sequence, voxa::StatusState state,
                   voxa::ErrorCode error) {
  const voxa::StatusPacket status{
      voxa::kProtocolVersion, sequence, state, error, voxa::kFirmwareMajor,
      voxa::kFirmwareMinor};
  std::uint8_t bytes[voxa::kStatusPacketSize]{};
  if (!voxa::serializeStatus(status, bytes, sizeof(bytes))) {
    return false;
  }
  return voxa::ble_transport::publishStatus(bytes, sizeof(bytes));
}

void recordPlaybackDriverFault(std::uint32_t nowMilliseconds) {
  playback.active = false;
  (void)voxa::drv2605l::setRealtimeValue(0U);
  voxa::recordDriverFault(nowMilliseconds, &driverHealth);
}

bool beginCurrentSegment(std::uint32_t nowMilliseconds) {
  const voxa::PatternSegment& segment =
      playback.program.segments[playback.segmentIndex];
  if (!setHapticOutput(segment.amplitudePercent,
                       playback.command.intensity)) {
    recordPlaybackDriverFault(nowMilliseconds);
    return false;
  }
  playback.segmentDeadlineMilliseconds =
      nowMilliseconds + segment.durationMilliseconds;
  return true;
}

bool preparePlayback(const voxa::CommandPacket& command,
                     std::uint32_t nowMilliseconds) {
  voxa::PatternProgram program{};
  if (!voxa::buildPatternProgram(command.patternId, &program) ||
      program.segmentCount == 0U) {
    return false;
  }

  playback.active = false;
  playback.waitingForRepeat = false;
  playback.command = command;
  playback.program = program;
  playback.segmentIndex = 0U;
  playback.repeatsRemaining = command.repeatCount;
  playback.lastDriverProbeMilliseconds = nowMilliseconds;
  return true;
}

bool activatePreparedPlayback(std::uint32_t nowMilliseconds) {
  playback.active = true;
  return beginCurrentSegment(nowMilliseconds);
}

PlaybackUpdate updatePlayback(std::uint32_t nowMilliseconds) {
  if (!playback.active) {
    return PlaybackUpdate::kNone;
  }

  if (timeReached(nowMilliseconds,
                  playback.lastDriverProbeMilliseconds +
                      kDriverProbeIntervalMilliseconds)) {
    playback.lastDriverProbeMilliseconds = nowMilliseconds;
    if (!voxa::drv2605l::isPresent()) {
      recordPlaybackDriverFault(nowMilliseconds);
      return PlaybackUpdate::kDriverFault;
    }
  }

  if (!timeReached(nowMilliseconds, playback.segmentDeadlineMilliseconds)) {
    return PlaybackUpdate::kNone;
  }

  if (playback.waitingForRepeat) {
    playback.waitingForRepeat = false;
    playback.segmentIndex = 0U;
    return beginCurrentSegment(nowMilliseconds)
               ? PlaybackUpdate::kNone
               : PlaybackUpdate::kDriverFault;
  }

  ++playback.segmentIndex;
  if (playback.segmentIndex < playback.program.segmentCount) {
    return beginCurrentSegment(nowMilliseconds)
               ? PlaybackUpdate::kNone
               : PlaybackUpdate::kDriverFault;
  }

  if (!setHapticOutput(0U, playback.command.intensity)) {
    recordPlaybackDriverFault(nowMilliseconds);
    return PlaybackUpdate::kDriverFault;
  }
  if (playback.repeatsRemaining > 1U) {
    --playback.repeatsRemaining;
    playback.waitingForRepeat = true;
    playback.segmentDeadlineMilliseconds =
        nowMilliseconds + playback.program.repeatGapMilliseconds;
    return PlaybackUpdate::kNone;
  }

  playback.active = false;
  return PlaybackUpdate::kCompleted;
}

void handleCommandFrame(const voxa::ble_transport::ReceivedCommandFrame& frame,
                        std::uint32_t nowMilliseconds) {
  const voxa::ParseCommandResult parsed =
      voxa::parseCommand(frame.bytes, frame.reportedLength);
  if (!parsed.valid) {
    (void)publishStatus(
        voxa::sequenceFromUntrustedCommand(frame.bytes, frame.reportedLength),
        voxa::StatusState::kRejected, parsed.error);
    return;
  }

  if (!voxa::canAcceptSequence(sequenceTracker, parsed.command.sequence) ||
      playback.active) {
    (void)publishStatus(parsed.command.sequence,
                        voxa::StatusState::kRejected,
                        voxa::ErrorCode::kInvalidCommand);
    return;
  }

  if (!driverHealth.ready || !voxa::drv2605l::isPresent()) {
    if (driverHealth.ready) {
      recordPlaybackDriverFault(nowMilliseconds);
    }
    (void)publishStatus(parsed.command.sequence,
                        voxa::StatusState::kRejected,
                        voxa::ErrorCode::kDriverFault);
    return;
  }

  if (!preparePlayback(parsed.command, nowMilliseconds)) {
    (void)publishStatus(parsed.command.sequence,
                        voxa::StatusState::kRejected,
                        voxa::ErrorCode::kInvalidCommand);
    return;
  }

  if (!publishStatus(parsed.command.sequence, voxa::StatusState::kAccepted,
                     voxa::ErrorCode::kNone)) {
    playback = PlaybackState{};
    return;
  }

  voxa::recordAcceptedSequence(&sequenceTracker, parsed.command.sequence);
  if (!activatePreparedPlayback(nowMilliseconds)) {
    (void)publishStatus(parsed.command.sequence,
                        voxa::StatusState::kRejected,
                        voxa::ErrorCode::kDriverFault);
  }
}

}  // namespace

int main() {
  voxa::clearSequenceTracker(&sequenceTracker);
  initializeSessionOutputs();

  const std::uint32_t startedAtMilliseconds = k_uptime_get_32();
  voxa::recordDriverRecovery(voxa::drv2605l::initialize(),
                             startedAtMilliseconds, &driverHealth);
  while (!voxa::ble_transport::initialize()) {
    k_sleep(K_MSEC(kBleInitializationRetryMilliseconds));
  }

  bool wasCentralConnected = voxa::ble_transport::isCentralConnected();

  while (true) {
    const std::uint32_t nowMilliseconds = k_uptime_get_32();
    const bool isCentralConnected =
        voxa::ble_transport::isCentralConnected();
    if (wasCentralConnected && !isCentralConnected) {
      sessionLight.hasCommand = false;
    }
    wasCentralConnected = isCentralConnected;

    if (voxa::driverRecoveryIsDue(driverHealth, nowMilliseconds)) {
      voxa::recordDriverRecovery(voxa::drv2605l::initialize(),
                                 nowMilliseconds, &driverHealth);
    }

    voxa::ble_transport::ReceivedCommandFrame commandFrame{};
    if (voxa::ble_transport::dequeueCommand(&commandFrame)) {
      handleCommandFrame(commandFrame, nowMilliseconds);
    }

    voxa::ble_transport::ReceivedSessionLightFrame lightFrame{};
    if (voxa::ble_transport::dequeueSessionLight(&lightFrame)) {
      handleSessionLightFrame(lightFrame, nowMilliseconds);
    }

    const PlaybackUpdate playbackUpdate = updatePlayback(nowMilliseconds);
    if (playbackUpdate == PlaybackUpdate::kCompleted) {
      voxa::recordCompletedSequence(&sequenceTracker,
                                    playback.command.sequence);
      (void)publishStatus(playback.command.sequence,
                          voxa::StatusState::kCompleted,
                          voxa::ErrorCode::kNone);
    } else if (playbackUpdate == PlaybackUpdate::kDriverFault) {
      (void)publishStatus(playback.command.sequence,
                          voxa::StatusState::kRejected,
                          voxa::ErrorCode::kDriverFault);
    }

    updateEmergencyBuzzerOutput(nowMilliseconds);
    updateSessionLightOutput(
        nowMilliseconds, k_ticks_to_us_floor32(k_uptime_ticks()));
    k_usleep(kMainLoopSleepMicroseconds);
  }

  return 0;
}
