#include <Arduino.h>
#include <Wire.h>

#include <Adafruit_DRV2605.h>
#include <NimBLEDevice.h>

#include <cstddef>
#include <cstdint>

#include "voxa_patterns.hpp"
#include "voxa_protocol.hpp"

namespace {

constexpr std::uint8_t kDrv2605Address = 0x5AU;
constexpr std::size_t kMailboxCapacity = 4U;
constexpr std::uint32_t kDriverProbeIntervalMilliseconds = 250U;

struct ReceivedCommandFrame {
  std::uint8_t bytes[voxa::kCommandPacketSize];
  std::size_t reportedLength;
};

struct CommandMailbox {
  ReceivedCommandFrame frames[kMailboxCapacity];
  std::size_t readIndex;
  std::size_t writeIndex;
  std::size_t count;
};

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
NimBLECharacteristic* statusCharacteristic = nullptr;
CommandMailbox commandMailbox{};
PlaybackState playback{};
voxa::SequenceTracker sequenceTracker{};
portMUX_TYPE mailboxMutex = portMUX_INITIALIZER_UNLOCKED;
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
  Wire.begin(A4, A5);
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
  if (statusCharacteristic == nullptr) {
    return false;
  }

  const voxa::StatusPacket status{
      voxa::kProtocolVersion, sequence, state, error, voxa::kFirmwareMajor,
      voxa::kFirmwareMinor};
  std::uint8_t bytes[voxa::kStatusPacketSize]{};
  if (!voxa::serializeStatus(status, bytes, sizeof(bytes))) {
    return false;
  }

  statusCharacteristic->setValue(bytes, sizeof(bytes));
  return statusCharacteristic->notify();
}

bool enqueueCommand(const std::uint8_t* bytes, std::size_t length) {
  if (bytes == nullptr && length > 0U) {
    return false;
  }

  bool enqueued = false;
  portENTER_CRITICAL(&mailboxMutex);
  if (commandMailbox.count < kMailboxCapacity) {
    ReceivedCommandFrame& frame =
        commandMailbox.frames[commandMailbox.writeIndex];
    for (std::size_t index = 0U; index < voxa::kCommandPacketSize; ++index) {
      frame.bytes[index] = index < length ? bytes[index] : 0U;
    }
    frame.reportedLength = length;
    commandMailbox.writeIndex =
        (commandMailbox.writeIndex + 1U) % kMailboxCapacity;
    ++commandMailbox.count;
    enqueued = true;
  }
  portEXIT_CRITICAL(&mailboxMutex);
  return enqueued;
}

bool dequeueCommand(ReceivedCommandFrame* output) {
  if (output == nullptr) {
    return false;
  }

  bool dequeued = false;
  portENTER_CRITICAL(&mailboxMutex);
  if (commandMailbox.count > 0U) {
    *output = commandMailbox.frames[commandMailbox.readIndex];
    commandMailbox.readIndex =
        (commandMailbox.readIndex + 1U) % kMailboxCapacity;
    --commandMailbox.count;
    dequeued = true;
  }
  portEXIT_CRITICAL(&mailboxMutex);
  return dequeued;
}

class CommandCallbacks final : public NimBLECharacteristicCallbacks {
 public:
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& connectionInfo) override {
    (void)connectionInfo;
    const NimBLEAttValue value = characteristic->getValue();
    if (!enqueueCommand(value.data(), value.size())) {
      publishStatus(voxa::sequenceFromUntrustedCommand(value.data(),
                                                       value.size()),
                    voxa::StatusState::kRejected,
                    voxa::ErrorCode::kInvalidCommand);
    }
  }
};

class ServerCallbacks final : public NimBLEServerCallbacks {
 public:
  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connectionInfo,
                    int reason) override {
    (void)server;
    (void)connectionInfo;
    (void)reason;
    NimBLEDevice::getAdvertising()->start();
  }
};

CommandCallbacks commandCallbacks;
ServerCallbacks serverCallbacks;

void initializeBluetooth() {
  NimBLEDevice::init(voxa::kDeviceName);
  NimBLEDevice::setPower(3);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(&serverCallbacks);
  NimBLEService* service = server->createService(voxa::kServiceUuid);
  NimBLECharacteristic* commandCharacteristic = service->createCharacteristic(
      voxa::kCommandCharacteristicUuid, NIMBLE_PROPERTY::WRITE);
  statusCharacteristic = service->createCharacteristic(
      voxa::kStatusCharacteristicUuid,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  commandCharacteristic->setCallbacks(&commandCallbacks);

  service->start();
  publishStatus(0U, voxa::StatusState::kCompleted, voxa::ErrorCode::kNone);

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(voxa::kServiceUuid);
  advertising->enableScanResponse(true);
  advertising->start();
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

void handleCommandFrame(const ReceivedCommandFrame& frame,
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
  initializeBluetooth();

  if (driverReady) {
    Serial.println("Voxa Cue firmware 1.0 ready");
  } else {
    Serial.println("DRV2605L not detected; haptic commands will be rejected");
  }
}

void loop() {
  const std::uint32_t nowMilliseconds = millis();

  ReceivedCommandFrame frame{};
  if (dequeueCommand(&frame)) {
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
