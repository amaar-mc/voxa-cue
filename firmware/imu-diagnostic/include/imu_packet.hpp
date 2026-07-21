#pragma once

#include <cstddef>
#include <cstdint>

namespace voxa::imu {

constexpr std::uint8_t kProtocolVersion = 1U;
constexpr std::size_t kSamplePacketSize = 20U;
constexpr std::size_t kInfoPacketSize = 8U;
constexpr std::uint8_t kFirmwareMajor = 1U;
constexpr std::uint8_t kFirmwareMinor = 1U;

enum class SensorKind : std::uint8_t {
  kNone = 0U,
  kMpu6050 = 1U,
  kLsm6Family = 2U,
  kUnsupported = 255U,
};

enum class SensorState : std::uint8_t {
  kReady = 0U,
  kNotFound = 1U,
  kUnsupported = 2U,
  kReadFault = 3U,
};

struct MotionSample {
  std::uint16_t sequence;
  std::uint32_t timestampMilliseconds;
  float accelerationXG;
  float accelerationYG;
  float accelerationZG;
  float gyroXDegreesPerSecond;
  float gyroYDegreesPerSecond;
  float gyroZDegreesPerSecond;
  bool sensorHealthy;
};

struct SensorInfo {
  SensorKind kind;
  std::uint8_t address;
  SensorState state;
  std::uint16_t sampleRateHertz;
};

bool serializeSample(const MotionSample& sample, std::uint8_t* output,
                     std::size_t outputLength);
bool serializeInfo(const SensorInfo& info, std::uint8_t* output,
                   std::size_t outputLength);

}  // namespace voxa::imu
