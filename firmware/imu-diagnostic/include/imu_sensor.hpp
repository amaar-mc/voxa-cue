#pragma once

#include <Arduino.h>
#include <Wire.h>

#include <cstddef>
#include <cstdint>

#include "imu_packet.hpp"

namespace voxa::imu {

struct SensorReading {
  float accelerationXG;
  float accelerationYG;
  float accelerationZG;
  float gyroXDegreesPerSecond;
  float gyroYDegreesPerSecond;
  float gyroZDegreesPerSecond;
};

class ImuSensor final {
 public:
  explicit ImuSensor(TwoWire& wire);

  SensorInfo begin();
  bool read(SensorReading* output);
  SensorInfo info() const;

 private:
  bool addressResponds(std::uint8_t address);
  bool writeRegister(std::uint8_t address, std::uint8_t reg,
                     std::uint8_t value);
  bool readRegister(std::uint8_t address, std::uint8_t reg,
                    std::uint8_t* value);
  bool readRegisters(std::uint8_t address, std::uint8_t firstRegister,
                     std::uint8_t* output, std::size_t length);
  bool detectMpu6050(std::uint8_t address);
  bool detectLsm6Family(std::uint8_t address);
  bool configureDetectedSensor();
  bool readMpu6050(SensorReading* output);
  bool readLsm6Family(SensorReading* output);
  void scanBus();

  TwoWire& wire_;
  SensorInfo info_;
};

}  // namespace voxa::imu
