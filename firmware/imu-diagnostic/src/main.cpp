#include <Arduino.h>
#include <ArduinoBLE.h>
#include <Wire.h>

#include <cstdint>

#include "imu_packet.hpp"
#include "imu_sensor.hpp"

namespace {

constexpr char kDeviceName[] = "Voxa IMU Lab";
constexpr char kServiceUuid[] = "7A3E1001-7C7B-4E25-9A5A-8D7C9F1A0001";
constexpr char kSampleUuid[] = "7A3E1002-7C7B-4E25-9A5A-8D7C9F1A0001";
constexpr char kInfoUuid[] = "7A3E1003-7C7B-4E25-9A5A-8D7C9F1A0001";
constexpr std::uint32_t kSampleIntervalMilliseconds =
    1000U / voxa::imu::kTargetSampleRateHertz;
constexpr std::uint32_t kRetryIntervalMilliseconds = 2000U;

BLEService motionService(kServiceUuid);
BLECharacteristic sampleCharacteristic(
    kSampleUuid, BLERead | BLENotify,
    static_cast<int>(voxa::imu::kSamplePacketSize), true);
BLECharacteristic infoCharacteristic(
    kInfoUuid, BLERead | BLENotify,
    static_cast<int>(voxa::imu::kInfoPacketSize), true);

voxa::imu::ImuSensor sensor(Wire);
voxa::imu::SensorInfo sensorInfo{voxa::imu::SensorKind::kNone, 0U,
                                 voxa::imu::SensorState::kNotFound,
                                 voxa::imu::kTargetSampleRateHertz};
std::uint16_t sequence = 0U;
std::uint32_t nextSampleMilliseconds = 0U;
std::uint32_t nextRetryMilliseconds = 0U;

bool timeReached(std::uint32_t nowMilliseconds,
                 std::uint32_t deadlineMilliseconds) {
  return static_cast<std::int32_t>(nowMilliseconds - deadlineMilliseconds) >=
         0;
}

void publishInfo() {
  std::uint8_t bytes[voxa::imu::kInfoPacketSize]{};
  if (voxa::imu::serializeInfo(sensorInfo, bytes, sizeof(bytes))) {
    infoCharacteristic.writeValue(bytes, static_cast<int>(sizeof(bytes)));
  }
}

void initializeSensor() {
  sensorInfo = sensor.begin();
  publishInfo();
  Serial.print("IMU state: ");
  Serial.print(static_cast<unsigned int>(sensorInfo.state));
  Serial.print(", kind: ");
  Serial.print(static_cast<unsigned int>(sensorInfo.kind));
  Serial.print(", address: 0x");
  Serial.println(sensorInfo.address, HEX);
}

void publishMotionSample(const voxa::imu::MotionSample& sample) {
  std::uint8_t bytes[voxa::imu::kSamplePacketSize]{};
  if (voxa::imu::serializeSample(sample, bytes, sizeof(bytes))) {
    sampleCharacteristic.writeValue(bytes, static_cast<int>(sizeof(bytes)));
  }
}

void publishSample(std::uint32_t nowMilliseconds) {
  voxa::imu::SensorReading reading{};
  const bool readSucceeded = sensor.read(&reading);
  if (!readSucceeded) {
    ++sequence;
    publishMotionSample(voxa::imu::MotionSample{
        sequence, nowMilliseconds, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F,
        false});
    sensorInfo.state = voxa::imu::SensorState::kReadFault;
    publishInfo();
    nextRetryMilliseconds = nowMilliseconds + kRetryIntervalMilliseconds;
    return;
  }

  ++sequence;
  const voxa::imu::MotionSample sample{
      sequence,
      nowMilliseconds,
      reading.accelerationXG,
      reading.accelerationYG,
      reading.accelerationZG,
      reading.gyroXDegreesPerSecond,
      reading.gyroYDegreesPerSecond,
      reading.gyroZDegreesPerSecond,
      true,
  };
  publishMotionSample(sample);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  const std::uint32_t serialDeadline = millis() + 1500U;
  while (!Serial && !timeReached(millis(), serialDeadline)) {
    delay(10U);
  }

  if (!BLE.begin()) {
    Serial.println("Bluetooth initialization failed");
    while (true) {
      delay(1000U);
    }
  }

  BLE.setLocalName(kDeviceName);
  BLE.setDeviceName(kDeviceName);
  BLE.setAdvertisedService(motionService);
  motionService.addCharacteristic(sampleCharacteristic);
  motionService.addCharacteristic(infoCharacteristic);
  BLE.addService(motionService);

  initializeSensor();
  BLE.advertise();
  Serial.println("Voxa IMU Lab advertising over BLE");
  nextSampleMilliseconds = millis();
  nextRetryMilliseconds = millis() + kRetryIntervalMilliseconds;
}

void loop() {
  BLE.poll();
  const std::uint32_t nowMilliseconds = millis();

  if (sensorInfo.state != voxa::imu::SensorState::kReady &&
      timeReached(nowMilliseconds, nextRetryMilliseconds)) {
    initializeSensor();
    nextRetryMilliseconds = nowMilliseconds + kRetryIntervalMilliseconds;
  }

  if (sensorInfo.state == voxa::imu::SensorState::kReady &&
      timeReached(nowMilliseconds, nextSampleMilliseconds)) {
    publishSample(nowMilliseconds);
    nextSampleMilliseconds += kSampleIntervalMilliseconds;
    if (timeReached(nowMilliseconds, nextSampleMilliseconds)) {
      nextSampleMilliseconds = nowMilliseconds + kSampleIntervalMilliseconds;
    }
  }
  delay(1U);
}
