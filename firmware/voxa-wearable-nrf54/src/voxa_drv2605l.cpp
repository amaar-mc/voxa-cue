#include "voxa_drv2605l.hpp"

#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/i2c.h>

#include <cstdint>

namespace voxa::drv2605l {
namespace {

constexpr std::uint16_t kAddress = 0x5AU;

constexpr std::uint8_t kStatusRegister = 0x00U;
constexpr std::uint8_t kModeRegister = 0x01U;
constexpr std::uint8_t kRealtimeInputRegister = 0x02U;
constexpr std::uint8_t kWaveformSequence1Register = 0x04U;
constexpr std::uint8_t kWaveformSequence2Register = 0x05U;
constexpr std::uint8_t kOverdriveRegister = 0x0DU;
constexpr std::uint8_t kSustainPositiveRegister = 0x0EU;
constexpr std::uint8_t kSustainNegativeRegister = 0x0FU;
constexpr std::uint8_t kBrakeRegister = 0x10U;
constexpr std::uint8_t kAudioMaximumRegister = 0x13U;
constexpr std::uint8_t kFeedbackControlRegister = 0x1AU;
constexpr std::uint8_t kControl3Register = 0x1DU;

constexpr std::uint8_t kRealtimePlaybackMode = 0x05U;
constexpr std::uint8_t kErmFeedbackMask = 0x7FU;
constexpr std::uint8_t kErmOpenLoopFlag = 0x20U;

const struct device* const i2cBus = DEVICE_DT_GET(DT_NODELABEL(i2c22));

bool writeRegister(std::uint8_t address, std::uint8_t value) {
  return i2c_reg_write_byte(i2cBus, kAddress, address, value) == 0;
}

bool readRegister(std::uint8_t address, std::uint8_t* output) {
  return output != nullptr &&
         i2c_reg_read_byte(i2cBus, kAddress, address, output) == 0;
}

}  // namespace

bool isPresent() {
  if (!device_is_ready(i2cBus)) {
    return false;
  }

  std::uint8_t status = 0U;
  return readRegister(kStatusRegister, &status);
}

bool initialize() {
  if (!isPresent()) {
    return false;
  }

  std::uint8_t feedbackControl = 0U;
  std::uint8_t control3 = 0U;
  if (!writeRegister(kModeRegister, 0x00U) ||
      !writeRegister(kRealtimeInputRegister, 0x00U) ||
      !writeRegister(kWaveformSequence1Register, 0x01U) ||
      !writeRegister(kWaveformSequence2Register, 0x00U) ||
      !writeRegister(kOverdriveRegister, 0x00U) ||
      !writeRegister(kSustainPositiveRegister, 0x00U) ||
      !writeRegister(kSustainNegativeRegister, 0x00U) ||
      !writeRegister(kBrakeRegister, 0x00U) ||
      !writeRegister(kAudioMaximumRegister, 0x64U) ||
      !readRegister(kFeedbackControlRegister, &feedbackControl) ||
      !writeRegister(kFeedbackControlRegister,
                     static_cast<std::uint8_t>(feedbackControl &
                                               kErmFeedbackMask)) ||
      !readRegister(kControl3Register, &control3) ||
      !writeRegister(kControl3Register,
                     static_cast<std::uint8_t>(control3 |
                                               kErmOpenLoopFlag)) ||
      !writeRegister(kModeRegister, kRealtimePlaybackMode) ||
      !writeRegister(kRealtimeInputRegister, 0x00U)) {
    return false;
  }

  return isPresent();
}

bool setRealtimeValue(std::uint8_t value) {
  return device_is_ready(i2cBus) &&
         writeRegister(kRealtimeInputRegister, value);
}

}  // namespace voxa::drv2605l

