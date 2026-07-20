#ifndef VOXA_HAPTIC_HARDWARE_HPP
#define VOXA_HAPTIC_HARDWARE_HPP

#include <cstdint>

namespace voxa::haptic_hardware {

enum class Driver : std::uint8_t {
  kDrv2605l = 1U,
};

enum class Actuator : std::uint8_t {
  kErm = 1U,
};

constexpr Driver kDriver = Driver::kDrv2605l;
constexpr Actuator kActuator = Actuator::kErm;
constexpr std::uint8_t kI2cAddress = 0x5AU;
constexpr bool kUsesDefaultWireBus = true;
constexpr bool kDirectPwmMotorOutputSupported = false;

}  // namespace voxa::haptic_hardware

#endif
