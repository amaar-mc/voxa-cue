#include "imu_sensor.hpp"

#include <Arduino.h>
#include <Wire.h>

#include <cstddef>
#include <cstdint>

namespace voxa::imu {
namespace {

constexpr std::uint8_t kMpuWhoAmIRegister = 0x75U;
constexpr std::uint8_t kMpuPowerManagementRegister = 0x6BU;
constexpr std::uint8_t kMpuSampleDividerRegister = 0x19U;
constexpr std::uint8_t kMpuConfigurationRegister = 0x1AU;
constexpr std::uint8_t kMpuGyroConfigurationRegister = 0x1BU;
constexpr std::uint8_t kMpuAccelConfigurationRegister = 0x1CU;
constexpr std::uint8_t kMpuDataStartRegister = 0x3BU;
constexpr float kMpuAccelCountsPerG = 8192.0F;
constexpr float kMpuGyroCountsPerDegreePerSecond = 65.5F;

constexpr std::uint8_t kLsmWhoAmIRegister = 0x0FU;
constexpr std::uint8_t kLsmAccelControlRegister = 0x10U;
constexpr std::uint8_t kLsmGyroControlRegister = 0x11U;
constexpr std::uint8_t kLsmDataStartRegister = 0x22U;
constexpr float kLsmAccelGPerCount = 0.000122F;
constexpr float kLsmGyroDegreesPerSecondPerCount = 0.0175F;

std::int16_t signedBigEndian(const std::uint8_t* bytes) {
  return static_cast<std::int16_t>(
      static_cast<std::uint16_t>(bytes[0]) << 8U |
      static_cast<std::uint16_t>(bytes[1]));
}

std::int16_t signedLittleEndian(const std::uint8_t* bytes) {
  return static_cast<std::int16_t>(
      static_cast<std::uint16_t>(bytes[1]) << 8U |
      static_cast<std::uint16_t>(bytes[0]));
}

bool isMpuIdentity(std::uint8_t identity) {
  return identity == 0x68U || identity == 0x70U || identity == 0x71U ||
         identity == 0x73U;
}

bool isLsm6Identity(std::uint8_t identity) {
  return identity == 0x69U || identity == 0x6AU || identity == 0x6CU;
}

}  // namespace

ImuSensor::ImuSensor(TwoWire& wire)
    : wire_(wire),
      info_{SensorKind::kNone, 0U, SensorState::kNotFound,
            kTargetSampleRateHertz} {}

SensorInfo ImuSensor::begin() {
  wire_.begin();
  wire_.setClock(400000U);
  scanBus();

  constexpr std::uint8_t candidateAddresses[] = {0x68U, 0x69U, 0x6AU, 0x6BU};
  for (const std::uint8_t address : candidateAddresses) {
    if (detectMpu6050(address) || detectLsm6Family(address)) {
      if (configureDetectedSensor()) {
        info_.state = SensorState::kReady;
      } else {
        info_.state = SensorState::kReadFault;
      }
      return info_;
    }
  }

  for (std::uint8_t address = 0x08U; address <= 0x77U; ++address) {
    if (addressResponds(address) && address != 0x5AU) {
      info_ = {SensorKind::kUnsupported, address, SensorState::kUnsupported,
               kTargetSampleRateHertz};
      return info_;
    }
  }

  info_ = {
      SensorKind::kNone, 0U, SensorState::kNotFound, kTargetSampleRateHertz};
  return info_;
}

bool ImuSensor::read(SensorReading* output) {
  if (output == nullptr || info_.state != SensorState::kReady) {
    return false;
  }

  switch (info_.kind) {
    case SensorKind::kMpu6050:
      return readMpu6050(output);
    case SensorKind::kLsm6Family:
      return readLsm6Family(output);
    case SensorKind::kNone:
    case SensorKind::kUnsupported:
      return false;
  }
  return false;
}

SensorInfo ImuSensor::info() const { return info_; }

bool ImuSensor::addressResponds(std::uint8_t address) {
  wire_.beginTransmission(address);
  return wire_.endTransmission() == 0U;
}

bool ImuSensor::writeRegister(std::uint8_t address, std::uint8_t reg,
                              std::uint8_t value) {
  wire_.beginTransmission(address);
  wire_.write(reg);
  wire_.write(value);
  return wire_.endTransmission() == 0U;
}

bool ImuSensor::readRegister(std::uint8_t address, std::uint8_t reg,
                             std::uint8_t* value) {
  return readRegisters(address, reg, value, 1U);
}

bool ImuSensor::readRegisters(std::uint8_t address,
                              std::uint8_t firstRegister,
                              std::uint8_t* output, std::size_t length) {
  if (output == nullptr || length == 0U || length > 32U) {
    return false;
  }

  wire_.beginTransmission(address);
  wire_.write(firstRegister);
  if (wire_.endTransmission(false) != 0U) {
    return false;
  }

  const std::size_t received = static_cast<std::size_t>(
      wire_.requestFrom(static_cast<int>(address), static_cast<int>(length)));
  if (received != length) {
    return false;
  }
  for (std::size_t index = 0U; index < length; ++index) {
    if (!wire_.available()) {
      return false;
    }
    output[index] = static_cast<std::uint8_t>(wire_.read());
  }
  return true;
}

bool ImuSensor::detectMpu6050(std::uint8_t address) {
  if (address != 0x68U && address != 0x69U) {
    return false;
  }
  std::uint8_t identity = 0U;
  if (!readRegister(address, kMpuWhoAmIRegister, &identity) ||
      !isMpuIdentity(identity)) {
    return false;
  }
  info_ = {SensorKind::kMpu6050, address, SensorState::kReadFault,
           kTargetSampleRateHertz};
  return true;
}

bool ImuSensor::detectLsm6Family(std::uint8_t address) {
  if (address != 0x6AU && address != 0x6BU) {
    return false;
  }
  std::uint8_t identity = 0U;
  if (!readRegister(address, kLsmWhoAmIRegister, &identity) ||
      !isLsm6Identity(identity)) {
    return false;
  }
  info_ = {SensorKind::kLsm6Family, address, SensorState::kReadFault,
           kTargetSampleRateHertz};
  return true;
}

bool ImuSensor::configureDetectedSensor() {
  if (info_.kind == SensorKind::kMpu6050) {
    return writeRegister(info_.address, kMpuPowerManagementRegister, 0x01U) &&
           writeRegister(info_.address, kMpuSampleDividerRegister, 0x13U) &&
           writeRegister(info_.address, kMpuConfigurationRegister, 0x03U) &&
           writeRegister(info_.address, kMpuGyroConfigurationRegister,
                         0x08U) &&
           writeRegister(info_.address, kMpuAccelConfigurationRegister,
                         0x08U);
  }
  if (info_.kind == SensorKind::kLsm6Family) {
    return writeRegister(info_.address, kLsmAccelControlRegister, 0x48U) &&
           writeRegister(info_.address, kLsmGyroControlRegister, 0x44U);
  }
  return false;
}

bool ImuSensor::readMpu6050(SensorReading* output) {
  std::uint8_t bytes[14]{};
  if (!readRegisters(info_.address, kMpuDataStartRegister, bytes,
                     sizeof(bytes))) {
    return false;
  }

  output->accelerationXG =
      static_cast<float>(signedBigEndian(&bytes[0])) / kMpuAccelCountsPerG;
  output->accelerationYG =
      static_cast<float>(signedBigEndian(&bytes[2])) / kMpuAccelCountsPerG;
  output->accelerationZG =
      static_cast<float>(signedBigEndian(&bytes[4])) / kMpuAccelCountsPerG;
  output->gyroXDegreesPerSecond =
      static_cast<float>(signedBigEndian(&bytes[8])) /
      kMpuGyroCountsPerDegreePerSecond;
  output->gyroYDegreesPerSecond =
      static_cast<float>(signedBigEndian(&bytes[10])) /
      kMpuGyroCountsPerDegreePerSecond;
  output->gyroZDegreesPerSecond =
      static_cast<float>(signedBigEndian(&bytes[12])) /
      kMpuGyroCountsPerDegreePerSecond;
  return true;
}

bool ImuSensor::readLsm6Family(SensorReading* output) {
  std::uint8_t bytes[12]{};
  if (!readRegisters(info_.address, kLsmDataStartRegister, bytes,
                     sizeof(bytes))) {
    return false;
  }

  output->gyroXDegreesPerSecond =
      static_cast<float>(signedLittleEndian(&bytes[0])) *
      kLsmGyroDegreesPerSecondPerCount;
  output->gyroYDegreesPerSecond =
      static_cast<float>(signedLittleEndian(&bytes[2])) *
      kLsmGyroDegreesPerSecondPerCount;
  output->gyroZDegreesPerSecond =
      static_cast<float>(signedLittleEndian(&bytes[4])) *
      kLsmGyroDegreesPerSecondPerCount;
  output->accelerationXG =
      static_cast<float>(signedLittleEndian(&bytes[6])) * kLsmAccelGPerCount;
  output->accelerationYG =
      static_cast<float>(signedLittleEndian(&bytes[8])) * kLsmAccelGPerCount;
  output->accelerationZG =
      static_cast<float>(signedLittleEndian(&bytes[10])) * kLsmAccelGPerCount;
  return true;
}

void ImuSensor::scanBus() {
  Serial.println("I2C scan (onboard plus A4/SDA, A5/SCL bus):");
  bool foundAny = false;
  for (std::uint8_t address = 0x08U; address <= 0x77U; ++address) {
    if (!addressResponds(address)) {
      continue;
    }
    foundAny = true;
    Serial.print("  found 0x");
    if (address < 0x10U) {
      Serial.print('0');
    }
    Serial.println(address, HEX);
  }
  if (!foundAny) {
    Serial.println("  no devices found; check 3V3, GND, SDA/A4, SCL/A5");
  }
}

}  // namespace voxa::imu
