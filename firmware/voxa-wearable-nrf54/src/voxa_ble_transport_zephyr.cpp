#include "voxa_ble_transport.hpp"

#include <zephyr/bluetooth/att.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/util.h>

#include <errno.h>
#include <string.h>

#include <cstddef>
#include <cstdint>

namespace voxa::ble_transport {
namespace {

constexpr std::size_t kCommandMailboxCapacity = 4U;
constexpr std::uint32_t kAdvertisingRetryMilliseconds = 250U;

#define BT_UUID_VOXA_SERVICE_VALUE                                           \
  BT_UUID_128_ENCODE(0x6F2A0001, 0x7C93, 0x4A58, 0xA9D4,                  \
                     0x3C52BBD1F110ULL)
#define BT_UUID_VOXA_COMMAND_VALUE                                           \
  BT_UUID_128_ENCODE(0x6F2A0002, 0x7C93, 0x4A58, 0xA9D4,                  \
                     0x3C52BBD1F110ULL)
#define BT_UUID_VOXA_STATUS_VALUE                                            \
  BT_UUID_128_ENCODE(0x6F2A0003, 0x7C93, 0x4A58, 0xA9D4,                  \
                     0x3C52BBD1F110ULL)
#define BT_UUID_VOXA_SESSION_LIGHT_VALUE                                     \
  BT_UUID_128_ENCODE(0x6F2A0004, 0x7C93, 0x4A58, 0xA9D4,                  \
                     0x3C52BBD1F110ULL)

#define BT_UUID_VOXA_SERVICE BT_UUID_DECLARE_128(BT_UUID_VOXA_SERVICE_VALUE)
#define BT_UUID_VOXA_COMMAND BT_UUID_DECLARE_128(BT_UUID_VOXA_COMMAND_VALUE)
#define BT_UUID_VOXA_STATUS BT_UUID_DECLARE_128(BT_UUID_VOXA_STATUS_VALUE)
#define BT_UUID_VOXA_SESSION_LIGHT                                           \
  BT_UUID_DECLARE_128(BT_UUID_VOXA_SESSION_LIGHT_VALUE)

K_MSGQ_DEFINE(commandMailbox, sizeof(ReceivedCommandFrame),
              kCommandMailboxCapacity, alignof(ReceivedCommandFrame));
K_MSGQ_DEFINE(sessionLightMailbox, sizeof(ReceivedSessionLightFrame), 1U,
              alignof(ReceivedSessionLightFrame));
K_MUTEX_DEFINE(statusMutex);
K_MUTEX_DEFINE(connectionMutex);

std::uint8_t statusValue[kStatusPacketSize]{
    kProtocolVersion,
    0U,
    0U,
    static_cast<std::uint8_t>(StatusState::kCompleted),
    static_cast<std::uint8_t>(ErrorCode::kNone),
    kFirmwareMajor,
    kFirmwareMinor,
};

struct bt_conn* activeConnection = nullptr;
atomic_t initialized = ATOMIC_INIT(0);
atomic_t centralConnected = ATOMIC_INIT(0);

const struct bt_data advertisingData[] = {
    BT_DATA_BYTES(BT_DATA_FLAGS, BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR),
    BT_DATA_BYTES(BT_DATA_UUID128_ALL, BT_UUID_VOXA_SERVICE_VALUE),
};

const struct bt_data scanResponseData[] = {
    BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME,
            sizeof(CONFIG_BT_DEVICE_NAME) - 1U),
};

void copyFrameBytes(const void* buffer, std::size_t length,
                    std::uint8_t* output, std::size_t outputSize) {
  memset(output, 0, outputSize);
  if (buffer == nullptr || length == 0U) {
    return;
  }

  const std::size_t copyLength = length < outputSize ? length : outputSize;
  memcpy(output, buffer, copyLength);
}

ssize_t readStatus(struct bt_conn* connection,
                   const struct bt_gatt_attr* attribute, void* buffer,
                   std::uint16_t length, std::uint16_t offset) {
  std::uint8_t snapshot[kStatusPacketSize]{};
  k_mutex_lock(&statusMutex, K_FOREVER);
  memcpy(snapshot, statusValue, sizeof(snapshot));
  k_mutex_unlock(&statusMutex);

  return bt_gatt_attr_read(connection, attribute, buffer, length, offset,
                           snapshot, sizeof(snapshot));
}

ssize_t writeCommand(struct bt_conn* connection,
                     const struct bt_gatt_attr* attribute, const void* buffer,
                     std::uint16_t length, std::uint16_t offset,
                     std::uint8_t flags) {
  ARG_UNUSED(connection);
  ARG_UNUSED(attribute);

  if (offset != 0U) {
    return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
  }
  if ((flags & BT_GATT_WRITE_FLAG_PREPARE) != 0U) {
    return BT_GATT_ERR(BT_ATT_ERR_NOT_SUPPORTED);
  }

  ReceivedCommandFrame frame{};
  copyFrameBytes(buffer, length, frame.bytes, sizeof(frame.bytes));
  frame.reportedLength = length;
  if (k_msgq_put(&commandMailbox, &frame, K_NO_WAIT) != 0) {
    return BT_GATT_ERR(BT_ATT_ERR_INSUFFICIENT_RESOURCES);
  }
  return static_cast<ssize_t>(length);
}

ssize_t writeSessionLight(struct bt_conn* connection,
                          const struct bt_gatt_attr* attribute,
                          const void* buffer, std::uint16_t length,
                          std::uint16_t offset, std::uint8_t flags) {
  ARG_UNUSED(connection);
  ARG_UNUSED(attribute);

  if (offset != 0U) {
    return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
  }
  if ((flags & BT_GATT_WRITE_FLAG_PREPARE) != 0U) {
    return BT_GATT_ERR(BT_ATT_ERR_NOT_SUPPORTED);
  }

  ReceivedSessionLightFrame frame{};
  copyFrameBytes(buffer, length, frame.bytes, sizeof(frame.bytes));
  frame.reportedLength = length;
  k_msgq_purge(&sessionLightMailbox);
  if (k_msgq_put(&sessionLightMailbox, &frame, K_NO_WAIT) != 0) {
    return BT_GATT_ERR(BT_ATT_ERR_INSUFFICIENT_RESOURCES);
  }
  return static_cast<ssize_t>(length);
}

void statusSubscriptionChanged(const struct bt_gatt_attr* attribute,
                               std::uint16_t value) {
  ARG_UNUSED(attribute);
  ARG_UNUSED(value);
}

BT_GATT_SERVICE_DEFINE(
    cueService,
    BT_GATT_PRIMARY_SERVICE(BT_UUID_VOXA_SERVICE),
    BT_GATT_CHARACTERISTIC(BT_UUID_VOXA_COMMAND, BT_GATT_CHRC_WRITE,
                           BT_GATT_PERM_WRITE, nullptr, writeCommand, nullptr),
    BT_GATT_CHARACTERISTIC(BT_UUID_VOXA_STATUS,
                           BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
                           BT_GATT_PERM_READ, readStatus, nullptr, nullptr),
    BT_GATT_CCC(statusSubscriptionChanged,
                BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
    BT_GATT_CHARACTERISTIC(BT_UUID_VOXA_SESSION_LIGHT, BT_GATT_CHRC_WRITE,
                           BT_GATT_PERM_WRITE, nullptr, writeSessionLight,
                           nullptr));

constexpr std::size_t kStatusAttributeIndex = 4U;

int startAdvertising() {
  const int stopResult = bt_le_adv_stop();
  if (stopResult != 0 && stopResult != -EALREADY) {
    return stopResult;
  }

  const int result = bt_le_adv_start(
      BT_LE_ADV_CONN_FAST_1, advertisingData, ARRAY_SIZE(advertisingData),
      scanResponseData, ARRAY_SIZE(scanResponseData));
  return result == -EALREADY ? 0 : result;
}

void restartAdvertising(struct k_work* work) {
  ARG_UNUSED(work);
  if (atomic_get(&initialized) == 0) {
    return;
  }

  if (startAdvertising() != 0) {
    k_work_reschedule(k_work_delayable_from_work(work),
                      K_MSEC(kAdvertisingRetryMilliseconds));
  }
}

K_WORK_DELAYABLE_DEFINE(advertisingRestartWork, restartAdvertising);

void connected(struct bt_conn* connection, std::uint8_t error) {
  if (error != 0U) {
    k_work_reschedule(&advertisingRestartWork,
                      K_MSEC(kAdvertisingRetryMilliseconds));
    return;
  }

  k_mutex_lock(&connectionMutex, K_FOREVER);
  if (activeConnection != nullptr) {
    bt_conn_unref(activeConnection);
  }
  activeConnection = bt_conn_ref(connection);
  atomic_set(&centralConnected, 1);
  k_mutex_unlock(&connectionMutex);
}

void disconnected(struct bt_conn* connection, std::uint8_t reason) {
  ARG_UNUSED(reason);
  k_mutex_lock(&connectionMutex, K_FOREVER);
  if (activeConnection == connection) {
    bt_conn_unref(activeConnection);
    activeConnection = nullptr;
  }
  atomic_clear(&centralConnected);
  k_mutex_unlock(&connectionMutex);

  k_msgq_purge(&commandMailbox);
  k_msgq_purge(&sessionLightMailbox);
  k_work_reschedule(&advertisingRestartWork, K_NO_WAIT);
}

BT_CONN_CB_DEFINE(connectionCallbacks) = {
    .connected = connected,
    .disconnected = disconnected,
};

struct bt_conn* referencedActiveConnection() {
  struct bt_conn* connection = nullptr;
  k_mutex_lock(&connectionMutex, K_FOREVER);
  if (activeConnection != nullptr) {
    connection = bt_conn_ref(activeConnection);
  }
  k_mutex_unlock(&connectionMutex);
  return connection;
}

}  // namespace

bool initialize() {
  if (atomic_get(&initialized) != 0) {
    return true;
  }

  const int enableResult = bt_enable(nullptr);
  if (enableResult != 0 && enableResult != -EALREADY) {
    return false;
  }

  atomic_set(&initialized, 1);
  const int advertisingResult = startAdvertising();
  if (advertisingResult != 0) {
    k_work_reschedule(&advertisingRestartWork,
                      K_MSEC(kAdvertisingRetryMilliseconds));
    return false;
  }
  return true;
}

void poll() {}

bool publishStatus(const std::uint8_t* bytes, std::size_t length) {
  if (bytes == nullptr || length != kStatusPacketSize) {
    return false;
  }

  struct bt_conn* connection = referencedActiveConnection();
  if (connection == nullptr) {
    return false;
  }

  const struct bt_gatt_attr* statusAttribute =
      &cueService.attrs[kStatusAttributeIndex];
  const bool subscribed = bt_gatt_is_subscribed(
      connection, statusAttribute, BT_GATT_CCC_NOTIFY);
  const int notifyResult =
      subscribed ? bt_gatt_notify(connection, statusAttribute, bytes, length)
                 : -ENOTCONN;
  bt_conn_unref(connection);
  if (notifyResult != 0) {
    return false;
  }

  k_mutex_lock(&statusMutex, K_FOREVER);
  memcpy(statusValue, bytes, length);
  k_mutex_unlock(&statusMutex);
  return true;
}

bool dequeueCommand(ReceivedCommandFrame* output) {
  return output != nullptr &&
         k_msgq_get(&commandMailbox, output, K_NO_WAIT) == 0;
}

bool dequeueSessionLight(ReceivedSessionLightFrame* output) {
  return output != nullptr &&
         k_msgq_get(&sessionLightMailbox, output, K_NO_WAIT) == 0;
}

bool isCentralConnected() {
  return atomic_get(&centralConnected) != 0;
}

}  // namespace voxa::ble_transport
