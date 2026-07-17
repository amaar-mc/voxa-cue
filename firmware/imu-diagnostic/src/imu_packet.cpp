#include "imu_packet.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace voxa::imu {
namespace {

std::int16_t scaledAndClamped(float value, float scale) {
  const float scaled = std::round(value * scale);
  const float minimum =
      static_cast<float>(std::numeric_limits<std::int16_t>::min());
  const float maximum =
      static_cast<float>(std::numeric_limits<std::int16_t>::max());
  if (scaled < minimum) {
    return std::numeric_limits<std::int16_t>::min();
  }
  if (scaled > maximum) {
    return std::numeric_limits<std::int16_t>::max();
  }
  return static_cast<std::int16_t>(scaled);
}

void writeUint16(std::uint16_t value, std::uint8_t* output) {
  output[0] = static_cast<std::uint8_t>(value & 0xFFU);
  output[1] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
}

void writeInt16(std::int16_t value, std::uint8_t* output) {
  writeUint16(static_cast<std::uint16_t>(value), output);
}

void writeUint32(std::uint32_t value, std::uint8_t* output) {
  output[0] = static_cast<std::uint8_t>(value & 0xFFU);
  output[1] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
  output[2] = static_cast<std::uint8_t>((value >> 16U) & 0xFFU);
  output[3] = static_cast<std::uint8_t>((value >> 24U) & 0xFFU);
}

}  // namespace

bool serializeSample(const MotionSample& sample, std::uint8_t* output,
                     std::size_t outputLength) {
  if (output == nullptr || outputLength != kSamplePacketSize) {
    return false;
  }

  output[0] = kProtocolVersion;
  output[1] = sample.sensorHealthy ? 1U : 0U;
  writeUint16(sample.sequence, &output[2]);
  writeUint32(sample.timestampMilliseconds, &output[4]);
  writeInt16(scaledAndClamped(sample.accelerationXG, 1000.0F), &output[8]);
  writeInt16(scaledAndClamped(sample.accelerationYG, 1000.0F), &output[10]);
  writeInt16(scaledAndClamped(sample.accelerationZG, 1000.0F), &output[12]);
  writeInt16(scaledAndClamped(sample.gyroXDegreesPerSecond, 10.0F),
             &output[14]);
  writeInt16(scaledAndClamped(sample.gyroYDegreesPerSecond, 10.0F),
             &output[16]);
  writeInt16(scaledAndClamped(sample.gyroZDegreesPerSecond, 10.0F),
             &output[18]);
  return true;
}

bool serializeInfo(const SensorInfo& info, std::uint8_t* output,
                   std::size_t outputLength) {
  if (output == nullptr || outputLength != kInfoPacketSize) {
    return false;
  }

  output[0] = kProtocolVersion;
  output[1] = static_cast<std::uint8_t>(info.kind);
  output[2] = info.address;
  output[3] = static_cast<std::uint8_t>(info.state);
  writeUint16(info.sampleRateHertz, &output[4]);
  output[6] = kFirmwareMajor;
  output[7] = kFirmwareMinor;
  return true;
}

}  // namespace voxa::imu
