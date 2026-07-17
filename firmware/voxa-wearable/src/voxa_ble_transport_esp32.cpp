#if defined(ARDUINO_ARCH_ESP32)

#include "voxa_ble_transport.hpp"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include <cstddef>
#include <cstdint>

namespace voxa::ble_transport {
namespace {

constexpr std::size_t kMailboxCapacity = 4U;

struct CommandMailbox {
  ReceivedCommandFrame frames[kMailboxCapacity];
  std::size_t readIndex;
  std::size_t writeIndex;
  std::size_t count;
};

NimBLECharacteristic* statusCharacteristic = nullptr;
CommandMailbox commandMailbox{};
ReceivedSessionLightFrame pendingSessionLight{};
bool hasPendingSessionLight = false;
bool centralConnected = false;
portMUX_TYPE mailboxMutex = portMUX_INITIALIZER_UNLOCKED;

bool enqueueCommand(const std::uint8_t* bytes, std::size_t length) {
  if (bytes == nullptr && length > 0U) {
    return false;
  }

  bool enqueued = false;
  portENTER_CRITICAL(&mailboxMutex);
  if (commandMailbox.count < kMailboxCapacity) {
    ReceivedCommandFrame& frame =
        commandMailbox.frames[commandMailbox.writeIndex];
    for (std::size_t index = 0U; index < kCommandPacketSize; ++index) {
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

class CommandCallbacks final : public NimBLECharacteristicCallbacks {
 public:
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& connectionInfo) override {
    (void)connectionInfo;
    const NimBLEAttValue value = characteristic->getValue();
    if (!enqueueCommand(value.data(), value.size())) {
      publishMailboxRejection(value.data(), value.size());
    }
  }
};

class SessionLightCallbacks final : public NimBLECharacteristicCallbacks {
 public:
  void onWrite(NimBLECharacteristic* characteristic,
               NimBLEConnInfo& connectionInfo) override {
    (void)connectionInfo;
    const NimBLEAttValue value = characteristic->getValue();
    portENTER_CRITICAL(&mailboxMutex);
    for (std::size_t index = 0U; index < kSessionLightPacketSize; ++index) {
      pendingSessionLight.bytes[index] =
          index < value.size() ? value.data()[index] : 0U;
    }
    pendingSessionLight.reportedLength = value.size();
    hasPendingSessionLight = true;
    portEXIT_CRITICAL(&mailboxMutex);
  }
};

class ServerCallbacks final : public NimBLEServerCallbacks {
 public:
  void onConnect(NimBLEServer* server,
                 NimBLEConnInfo& connectionInfo) override {
    (void)server;
    (void)connectionInfo;
    portENTER_CRITICAL(&mailboxMutex);
    centralConnected = true;
    portEXIT_CRITICAL(&mailboxMutex);
  }

  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connectionInfo,
                    int reason) override {
    (void)server;
    (void)connectionInfo;
    (void)reason;
    portENTER_CRITICAL(&mailboxMutex);
    centralConnected = false;
    portEXIT_CRITICAL(&mailboxMutex);
    NimBLEDevice::getAdvertising()->start();
  }
};

CommandCallbacks commandCallbacks;
SessionLightCallbacks sessionLightCallbacks;
ServerCallbacks serverCallbacks;

}  // namespace

bool initialize() {
  NimBLEDevice::init(kDeviceName);
  NimBLEDevice::setPower(3);

  NimBLEServer* server = NimBLEDevice::createServer();
  if (server == nullptr) {
    return false;
  }
  server->setCallbacks(&serverCallbacks);

  NimBLEService* service = server->createService(kServiceUuid);
  if (service == nullptr) {
    return false;
  }

  NimBLECharacteristic* commandCharacteristic = service->createCharacteristic(
      kCommandCharacteristicUuid, NIMBLE_PROPERTY::WRITE);
  statusCharacteristic = service->createCharacteristic(
      kStatusCharacteristicUuid,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* sessionLightCharacteristic =
      service->createCharacteristic(kSessionLightCharacteristicUuid,
                                    NIMBLE_PROPERTY::WRITE);
  if (commandCharacteristic == nullptr || statusCharacteristic == nullptr ||
      sessionLightCharacteristic == nullptr) {
    statusCharacteristic = nullptr;
    return false;
  }
  commandCharacteristic->setCallbacks(&commandCallbacks);
  sessionLightCharacteristic->setCallbacks(&sessionLightCallbacks);

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  if (advertising == nullptr) {
    statusCharacteristic = nullptr;
    return false;
  }
  advertising->addServiceUUID(kServiceUuid);
  advertising->enableScanResponse(true);
  return advertising->start();
}

void poll() {}

bool publishStatus(const std::uint8_t* bytes, std::size_t length) {
  if (statusCharacteristic == nullptr || bytes == nullptr ||
      length != kStatusPacketSize) {
    return false;
  }

  statusCharacteristic->setValue(bytes, length);
  return statusCharacteristic->notify();
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

bool dequeueSessionLight(ReceivedSessionLightFrame* output) {
  if (output == nullptr) {
    return false;
  }

  bool dequeued = false;
  portENTER_CRITICAL(&mailboxMutex);
  if (hasPendingSessionLight) {
    *output = pendingSessionLight;
    hasPendingSessionLight = false;
    dequeued = true;
  }
  portEXIT_CRITICAL(&mailboxMutex);
  return dequeued;
}

bool isCentralConnected() {
  bool connected = false;
  portENTER_CRITICAL(&mailboxMutex);
  connected = centralConnected;
  portEXIT_CRITICAL(&mailboxMutex);
  return connected;
}

}  // namespace voxa::ble_transport

#endif
