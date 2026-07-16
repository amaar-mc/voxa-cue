#include <Arduino.h>
#include <Wire.h>

#include <Adafruit_DRV2605.h>

#include <cstddef>
#include <cstdint>

#include "voxa_ble_transport.hpp"
#include "voxa_patterns.hpp"
#include "voxa_protocol.hpp"

namespace {

constexpr std::uint8_t kDrv2605Address = 0x5AU;
constexpr std::uint32_t kDriverProbeIntervalMilliseconds = 250U;

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

Adafruit_DRV2605 hapticDriver;
PlaybackState playback{};
voxa::SequenceTracker sequenceTracker{};
bool driverReady = false;

bool timeReached(std::uint32_t nowMilliseconds,
                 std::uint32_t deadlineMilliseconds) {
  return static_cast<std::int32_t>(nowMilliseconds - deadlineMilliseconds) >=
         0;
}

bool driverPresent() {
  Wire.beginTransmission(kDrv2605Address);
  return Wire.endTransmission() == 0U;
}

bool initializeHapticDriver() {
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
  const std::uint8_t amplitude =
      segment.motorEnabled
          ? voxa::amplitudeForIntensity(playback.command.intensity)
          : 0U;
  hapticDriver.setRealtimeValue(amplitude);
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

  hapticDriver.setRealtimeValue(0U);
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
    Serial.println("Voxa Cue firmware 1.0 ready");
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
