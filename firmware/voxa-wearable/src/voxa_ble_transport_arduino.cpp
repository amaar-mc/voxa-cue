#if defined(ARDUINO_ARCH_SAMD)

#include "voxa_ble_transport.hpp"

#include <ArduinoBLE.h>

#include <cstddef>
#include <cstdint>

namespace voxa::ble_transport {
namespace {

constexpr std::size_t kMailboxCapacity = 4U;
constexpr int kMaximumReceivedValueLength = 20;

#if defined(VOXA_DIRECT_PWM_DIAGNOSTIC)
constexpr char kAdvertisedDeviceName[] = "Voxa D2";
#else
constexpr const char* kAdvertisedDeviceName = kDeviceName;
#endif

struct CommandMailbox {
  ReceivedCommandFrame frames[kMailboxCapacity];
  std::size_t readIndex;
  std::size_t writeIndex;
  std::size_t count;
};

BLEService cueService(kServiceUuid);
BLECharacteristic commandCharacteristic(kCommandCharacteristicUuid, BLEWrite,
                                        kMaximumReceivedValueLength, false);
BLECharacteristic statusCharacteristic(kStatusCharacteristicUuid,
                                       BLERead | BLENotify,
                                       static_cast<int>(kStatusPacketSize),
                                       true);
BLECharacteristic sessionLightCharacteristic(
    kSessionLightCharacteristicUuid, BLEWrite,
    static_cast<int>(kSessionLightPacketSize), true);
CommandMailbox commandMailbox{};
ReceivedSessionLightFrame pendingSessionLight{};
bool hasPendingSessionLight = false;
bool initialized = false;

bool enqueueCommand(const std::uint8_t* bytes, std::size_t length) {
  if ((bytes == nullptr && length > 0U) ||
      commandMailbox.count >= kMailboxCapacity) {
    return false;
  }

  ReceivedCommandFrame& frame =
      commandMailbox.frames[commandMailbox.writeIndex];
  for (std::size_t index = 0U; index < kCommandPacketSize; ++index) {
    frame.bytes[index] = index < length ? bytes[index] : 0U;
  }
  frame.reportedLength = length;
  commandMailbox.writeIndex =
      (commandMailbox.writeIndex + 1U) % kMailboxCapacity;
  ++commandMailbox.count;
  return true;
}

void publishMailboxRejection(const std::uint8_t* bytes, std::size_t length) {
  const StatusPacket status{
      kProtocolVersion,
      sequenceFromUntrustedCommand(bytes, length),
      StatusState::kRejected,
      ErrorCode::kInvalidCommand,
      kFirmwareMajor,
      kFirmwareMinor,
  };
  std::uint8_t statusBytes[kStatusPacketSize]{};
  if (serializeStatus(status, statusBytes, sizeof(statusBytes))) {
    publishStatus(statusBytes, sizeof(statusBytes));
  }
}

void commandWritten(BLEDevice central, BLECharacteristic characteristic) {
  (void)central;
  const int receivedLength = characteristic.valueLength();
  const std::uint8_t* receivedBytes = characteristic.value();
  if (receivedLength < 0 ||
      !enqueueCommand(receivedBytes,
                      static_cast<std::size_t>(receivedLength))) {
    publishMailboxRejection(
        receivedBytes,
        receivedLength > 0 ? static_cast<std::size_t>(receivedLength) : 0U);
  }
}

void sessionLightWritten(BLEDevice central, BLECharacteristic characteristic) {
  (void)central;
  const int receivedLength = characteristic.valueLength();
  const std::uint8_t* receivedBytes = characteristic.value();
  for (std::size_t index = 0U; index < kSessionLightPacketSize; ++index) {
    pendingSessionLight.bytes[index] =
        receivedLength > 0 && index < static_cast<std::size_t>(receivedLength)
            ? receivedBytes[index]
            : 0U;
  }
  pendingSessionLight.reportedLength =
      receivedLength > 0 ? static_cast<std::size_t>(receivedLength) : 0U;
  hasPendingSessionLight = true;
}

}  // namespace

bool initialize() {
  if (!BLE.begin()) {
    return false;
  }

  BLE.setLocalName(kAdvertisedDeviceName);
  BLE.setDeviceName(kAdvertisedDeviceName);
  BLE.setAdvertisedService(cueService);
  cueService.addCharacteristic(commandCharacteristic);
  cueService.addCharacteristic(statusCharacteristic);
  cueService.addCharacteristic(sessionLightCharacteristic);
  BLE.addService(cueService);

  commandCharacteristic.setEventHandler(BLEWritten, commandWritten);
  sessionLightCharacteristic.setEventHandler(BLEWritten, sessionLightWritten);

  initialized = BLE.advertise() != 0;
  return initialized;
}

void poll() {
  if (initialized) {
    BLE.poll();
  }
}

bool publishStatus(const std::uint8_t* bytes, std::size_t length) {
  if (!initialized || bytes == nullptr || length != kStatusPacketSize) {
    return false;
  }

  return statusCharacteristic.writeValue(bytes, static_cast<int>(length)) ==
         static_cast<int>(length);
}

bool dequeueCommand(ReceivedCommandFrame* output) {
  if (output == nullptr || commandMailbox.count == 0U) {
    return false;
  }

  *output = commandMailbox.frames[commandMailbox.readIndex];
  commandMailbox.readIndex =
      (commandMailbox.readIndex + 1U) % kMailboxCapacity;
  --commandMailbox.count;
  return true;
}

bool dequeueSessionLight(ReceivedSessionLightFrame* output) {
  if (output == nullptr || !hasPendingSessionLight) {
    return false;
  }
  *output = pendingSessionLight;
  hasPendingSessionLight = false;
  return true;
}

bool isCentralConnected() {
  return initialized && BLE.connected();
}

}  // namespace voxa::ble_transport

#endif
