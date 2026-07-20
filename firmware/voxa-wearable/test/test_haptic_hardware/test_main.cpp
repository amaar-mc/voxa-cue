#include <unity.h>

#include "voxa_haptic_hardware.hpp"

namespace {

void productionHapticsRequireDrv2605lOverDefaultI2c() {
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::haptic_hardware::Driver::kDrv2605l),
      static_cast<std::uint8_t>(voxa::haptic_hardware::kDriver));
  TEST_ASSERT_EQUAL_UINT8(0x5AU, voxa::haptic_hardware::kI2cAddress);
  TEST_ASSERT_TRUE(voxa::haptic_hardware::kUsesDefaultWireBus);
  TEST_ASSERT_FALSE(voxa::haptic_hardware::kDirectPwmMotorOutputSupported);
}

void productionHapticsUseAnErm() {
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::haptic_hardware::Actuator::kErm),
      static_cast<std::uint8_t>(voxa::haptic_hardware::kActuator));
}

}  // namespace

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(productionHapticsRequireDrv2605lOverDefaultI2c);
  RUN_TEST(productionHapticsUseAnErm);
  return UNITY_END();
}
