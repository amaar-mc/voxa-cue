#include <Arduino.h>

#if !defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
#include <Wire.h>

#include <Adafruit_DRV2605.h>
#endif

#include <cstddef>
#include <cstdint>

#include "voxa_ble_transport.hpp"
#include "voxa_patterns.hpp"
#include "voxa_protocol.hpp"

namespace {

constexpr std::uint32_t kDriverProbeIntervalMilliseconds = 250U;

#if defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
constexpr std::uint8_t kDiagnosticControlPin = 2U;
constexpr std::uint8_t kDiagnosticSoftPwm = 150U;
constexpr std::uint8_t kDiagnosticMediumPwm = 185U;
constexpr std::uint8_t kDiagnosticStrongPwm = 220U;
#else
constexpr std::uint8_t kDrv2605Address = 0x5AU;
#endif

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

enum class PlaybackUpdate : std::uint8_t {
  kNone = 0U,
  kCompleted = 1U,
  kDriverFault = 2U,
};

#if !defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
Adafruit_DRV2605 hapticDriver;
#endif
PlaybackState playback{};
voxa::SequenceTracker sequenceTracker{};
bool driverReady = false;

bool timeReached(std::uint32_t nowMilliseconds,
                 std::uint32_t deadlineMilliseconds) {
  return static_cast<std::int32_t>(nowMilliseconds - deadlineMilliseconds) >=
         0;
}

bool driverPresent() {
#if defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
  return true;
#else
  Wire.beginTransmission(kDrv2605Address);
  return Wire.endTransmission() == 0U;
#endif
}

bool initializeHapticDriver() {
#if defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
  pinMode(kDiagnosticControlPin, OUTPUT);
  analogWriteResolution(8);
  analogWrite(kDiagnosticControlPin, 0U);
  return true;
#else
#if defined(ARDUINO_ARCH_ESP32)
  Wire.begin(A4, A5);
#else
  Wire.begin();
#endif
  if (!hapticDriver.begin(&Wire)) {
    return false;
  }

  hapticDriver.useLRA();
  hapticDriver.setMode(DRV2605_MODE_REALTIME);
  hapticDriver.setRealtimeValue(0U);
  return driverPresent();
#endif
}

#if defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
std::uint8_t diagnosticPwmForIntensity(voxa::Intensity intensity) {
  switch (intensity) {
    case voxa::Intensity::kSoft:
      return kDiagnosticSoftPwm;
    case voxa::Intensity::kMedium:
      return kDiagnosticMediumPwm;
    case voxa::Intensity::kStrong:
      return kDiagnosticStrongPwm;
  }
  return 0U;
}
#endif

void setHapticOutput(std::uint8_t amplitudePercent,
                     voxa::Intensity intensity) {
#if defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
  const std::uint16_t boundedPercent =
      amplitudePercent > 100U ? 100U : amplitudePercent;
  const std::uint8_t pwm = static_cast<std::uint8_t>(
      static_cast<std::uint16_t>(diagnosticPwmForIntensity(intensity)) *
      boundedPercent / 100U);
  analogWrite(kDiagnosticControlPin, pwm);
#else
  const std::uint8_t amplitude =
      voxa::scaledAmplitudeForIntensity(intensity, amplitudePercent);
  hapticDriver.setRealtimeValue(amplitude);
#endif
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

void beginCurrentSegment(std::uint32_t nowMilliseconds) {
  const voxa::PatternSegment& segment =
      playback.program.segments[playback.segmentIndex];
  setHapticOutput(segment.amplitudePercent, playback.command.intensity);
  playback.segmentDeadlineMilliseconds =
      nowMilliseconds + segment.durationMilliseconds;
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

void activatePreparedPlayback(std::uint32_t nowMilliseconds) {
  playback.active = true;
  beginCurrentSegment(nowMilliseconds);
}

PlaybackUpdate updatePlayback(std::uint32_t nowMilliseconds) {
  if (!playback.active) {
    return PlaybackUpdate::kNone;
  }

  if (timeReached(nowMilliseconds,
                  playback.lastDriverProbeMilliseconds +
                      kDriverProbeIntervalMilliseconds)) {
    playback.lastDriverProbeMilliseconds = nowMilliseconds;
    if (!driverPresent()) {
      playback.active = false;
      driverReady = false;
      return PlaybackUpdate::kDriverFault;
    }
  }

  if (!timeReached(nowMilliseconds, playback.segmentDeadlineMilliseconds)) {
    return PlaybackUpdate::kNone;
  }

  if (playback.waitingForRepeat) {
    playback.waitingForRepeat = false;
    playback.segmentIndex = 0U;
    beginCurrentSegment(nowMilliseconds);
    return PlaybackUpdate::kNone;
  }

  ++playback.segmentIndex;
  if (playback.segmentIndex < playback.program.segmentCount) {
    beginCurrentSegment(nowMilliseconds);
    return PlaybackUpdate::kNone;
  }

  setHapticOutput(0U, playback.command.intensity);
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
    publishStatus(voxa::sequenceFromUntrustedCommand(frame.bytes,
                                                     frame.reportedLength),
                  voxa::StatusState::kRejected, parsed.error);
    return;
  }

  if (!voxa::canAcceptSequence(sequenceTracker, parsed.command.sequence) ||
      playback.active) {
    publishStatus(parsed.command.sequence, voxa::StatusState::kRejected,
                  voxa::ErrorCode::kInvalidCommand);
    return;
  }

  if (!driverReady || !driverPresent()) {
    driverReady = false;
    publishStatus(parsed.command.sequence, voxa::StatusState::kRejected,
                  voxa::ErrorCode::kDriverFault);
    return;
  }

  if (!preparePlayback(parsed.command, nowMilliseconds)) {
    publishStatus(parsed.command.sequence, voxa::StatusState::kRejected,
                  voxa::ErrorCode::kInvalidCommand);
    return;
  }

  if (!publishStatus(parsed.command.sequence, voxa::StatusState::kAccepted,
                     voxa::ErrorCode::kNone)) {
    playback = PlaybackState{};
    return;
  }

  voxa::recordAcceptedSequence(&sequenceTracker, parsed.command.sequence);
  activatePreparedPlayback(nowMilliseconds);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  voxa::clearSequenceTracker(&sequenceTracker);
  driverReady = initializeHapticDriver();
  const bool bluetoothReady = voxa::ble_transport::initialize();
  if (bluetoothReady) {
    publishStatus(0U, voxa::StatusState::kCompleted,
                  voxa::ErrorCode::kNone);
  }

  if (!bluetoothReady) {
    Serial.println("Bluetooth initialization failed");
  } else if (driverReady) {
#if defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
    Serial.println("Voxa Cue D2 PWM diagnostic ready");
#else
    Serial.println("Voxa Cue firmware 1.1 ready");
#endif
  } else {
    Serial.println("DRV2605L not detected; haptic commands will be rejected");
  }
}

void loop() {
  const std::uint32_t nowMilliseconds = millis();
  voxa::ble_transport::poll();

  voxa::ble_transport::ReceivedCommandFrame frame{};
  if (voxa::ble_transport::dequeueCommand(&frame)) {
    handleCommandFrame(frame, nowMilliseconds);
  }

  const PlaybackUpdate update = updatePlayback(nowMilliseconds);
  if (update == PlaybackUpdate::kCompleted) {
    voxa::recordCompletedSequence(&sequenceTracker,
                                  playback.command.sequence);
    publishStatus(playback.command.sequence, voxa::StatusState::kCompleted,
                  voxa::ErrorCode::kNone);
  } else if (update == PlaybackUpdate::kDriverFault) {
    publishStatus(playback.command.sequence, voxa::StatusState::kRejected,
                  voxa::ErrorCode::kDriverFault);
  }

  delay(1U);
}
