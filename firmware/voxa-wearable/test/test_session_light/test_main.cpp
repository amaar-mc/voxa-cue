#include <unity.h>

#include <cstdint>

#include "voxa_session_light.hpp"

namespace {

void validSessionLightPacketParses() {
  const std::uint8_t bytes[voxa::kSessionLightPacketSize]{
      voxa::kProtocolVersion,
      static_cast<std::uint8_t>(voxa::SessionLightMode::kActive), 42U};

  const voxa::ParseSessionLightResult parsed =
      voxa::parseSessionLight(bytes, sizeof(bytes));

  TEST_ASSERT_TRUE(parsed.valid);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::SessionLightMode::kActive),
      static_cast<std::uint8_t>(parsed.command.mode));
  TEST_ASSERT_EQUAL_UINT8(42U, parsed.command.progressPercent);
}

void emergencySessionLightPacketParses() {
  const std::uint8_t bytes[voxa::kSessionLightPacketSize]{
      voxa::kProtocolVersion,
      static_cast<std::uint8_t>(voxa::SessionLightMode::kOvertimeEmergency),
      100U};

  const voxa::ParseSessionLightResult parsed =
      voxa::parseSessionLight(bytes, sizeof(bytes));

  TEST_ASSERT_TRUE(parsed.valid);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(
          voxa::SessionLightMode::kOvertimeEmergency),
      static_cast<std::uint8_t>(parsed.command.mode));
}

void malformedSessionLightPacketsAreRejected() {
  const std::uint8_t wrongVersion[voxa::kSessionLightPacketSize]{
      2U, static_cast<std::uint8_t>(voxa::SessionLightMode::kActive), 42U};
  const std::uint8_t wrongMode[voxa::kSessionLightPacketSize]{1U, 5U, 42U};
  const std::uint8_t excessiveProgress[voxa::kSessionLightPacketSize]{
      1U, static_cast<std::uint8_t>(voxa::SessionLightMode::kActive), 101U};

  TEST_ASSERT_FALSE(
      voxa::parseSessionLight(nullptr, voxa::kSessionLightPacketSize).valid);
  TEST_ASSERT_FALSE(
      voxa::parseSessionLight(wrongVersion, sizeof(wrongVersion)).valid);
  TEST_ASSERT_FALSE(voxa::parseSessionLight(wrongMode, sizeof(wrongMode)).valid);
  TEST_ASSERT_FALSE(
      voxa::parseSessionLight(excessiveProgress, sizeof(excessiveProgress))
          .valid);
  TEST_ASSERT_FALSE(
      voxa::parseSessionLight(excessiveProgress,
                              voxa::kSessionLightPacketSize - 1U)
          .valid);
}

void activeColorMovesThroughGreenYellowOrangeRed() {
  const voxa::RgbColor green = voxa::activeSessionColor(0U);
  const voxa::RgbColor yellow = voxa::activeSessionColor(50U);
  const voxa::RgbColor orange = voxa::activeSessionColor(75U);
  const voxa::RgbColor red = voxa::activeSessionColor(100U);

  TEST_ASSERT_EQUAL_UINT8(0U, green.red);
  TEST_ASSERT_EQUAL_UINT8(255U, green.green);
  TEST_ASSERT_EQUAL_UINT8(0U, green.blue);
  TEST_ASSERT_EQUAL_UINT8(255U, yellow.red);
  TEST_ASSERT_EQUAL_UINT8(255U, yellow.green);
  TEST_ASSERT_EQUAL_UINT8(0U, yellow.blue);
  TEST_ASSERT_EQUAL_UINT8(255U, orange.red);
  TEST_ASSERT_EQUAL_UINT8(128U, orange.green);
  TEST_ASSERT_EQUAL_UINT8(0U, orange.blue);
  TEST_ASSERT_EQUAL_UINT8(255U, red.red);
  TEST_ASSERT_EQUAL_UINT8(0U, red.green);
  TEST_ASSERT_EQUAL_UINT8(0U, red.blue);
}

void activeColorInterpolatesBetweenMilestones() {
  const voxa::RgbColor quarter = voxa::activeSessionColor(25U);
  const voxa::RgbColor nearlyDone = voxa::activeSessionColor(90U);

  TEST_ASSERT_UINT8_WITHIN(1U, 128U, quarter.red);
  TEST_ASSERT_EQUAL_UINT8(255U, quarter.green);
  TEST_ASSERT_EQUAL_UINT8(0U, quarter.blue);
  TEST_ASSERT_EQUAL_UINT8(255U, nearlyDone.red);
  TEST_ASSERT_UINT8_WITHIN(1U, 51U, nearlyDone.green);
  TEST_ASSERT_EQUAL_UINT8(0U, nearlyDone.blue);
}

void resolvedLightHandlesPauseOvertimeAndOff() {
  const voxa::SessionLightCommand paused{
      voxa::kProtocolVersion, voxa::SessionLightMode::kPaused, 75U};
  const voxa::SessionLightCommand overtime{
      voxa::kProtocolVersion, voxa::SessionLightMode::kOvertime, 100U};
  const voxa::SessionLightCommand emergency{
      voxa::kProtocolVersion,
      voxa::SessionLightMode::kOvertimeEmergency,
      100U};
  const voxa::SessionLightCommand off{
      voxa::kProtocolVersion, voxa::SessionLightMode::kOff, 0U};

  const voxa::RgbColor pausedColor = voxa::resolvedSessionColor(paused, 900U);
  const voxa::RgbColor overtimeOn = voxa::resolvedSessionColor(overtime, 499U);
  const voxa::RgbColor overtimeOff = voxa::resolvedSessionColor(overtime, 500U);
  const voxa::RgbColor emergencyOn =
      voxa::resolvedSessionColor(emergency, 499U);
  const voxa::RgbColor emergencyOff =
      voxa::resolvedSessionColor(emergency, 500U);
  const voxa::RgbColor offColor = voxa::resolvedSessionColor(off, 0U);

  TEST_ASSERT_EQUAL_UINT8(255U, pausedColor.red);
  TEST_ASSERT_EQUAL_UINT8(128U, pausedColor.green);
  TEST_ASSERT_EQUAL_UINT8(255U, overtimeOn.red);
  TEST_ASSERT_EQUAL_UINT8(0U, overtimeOn.green);
  TEST_ASSERT_EQUAL_UINT8(0U, overtimeOff.red);
  TEST_ASSERT_EQUAL_UINT8(0U, overtimeOff.green);
  TEST_ASSERT_EQUAL_UINT8(255U, emergencyOn.red);
  TEST_ASSERT_EQUAL_UINT8(0U, emergencyOn.green);
  TEST_ASSERT_EQUAL_UINT8(0U, emergencyOff.red);
  TEST_ASSERT_EQUAL_UINT8(0U, emergencyOff.green);
  TEST_ASSERT_EQUAL_UINT8(0U, offColor.red);
  TEST_ASSERT_EQUAL_UINT8(0U, offColor.green);
  TEST_ASSERT_EQUAL_UINT8(0U, offColor.blue);
}

void emergencyBuzzerSoundsOnceForExactlyTwoSeconds() {
  voxa::EmergencyBuzzerState state{};

  TEST_ASSERT_FALSE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kActive, 100U, &state));
  TEST_ASSERT_TRUE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 1000U, &state));
  TEST_ASSERT_EQUAL_UINT32(3000U, state.stopAtMilliseconds);

  TEST_ASSERT_TRUE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 2000U, &state));
  TEST_ASSERT_EQUAL_UINT32(3000U, state.stopAtMilliseconds);
  TEST_ASSERT_TRUE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 2999U, &state));
  TEST_ASSERT_FALSE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 3000U, &state));
  TEST_ASSERT_FALSE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 4000U, &state));

  voxa::resetEmergencyBuzzerState(&state);
  TEST_ASSERT_FALSE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kActive, 5000U, &state));
  TEST_ASSERT_TRUE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 6000U, &state));
}

void disconnectSilencesWithoutRetriggeringTheSession() {
  voxa::EmergencyBuzzerState state{};

  TEST_ASSERT_FALSE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kActive, 100U, &state));
  TEST_ASSERT_TRUE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 1000U, &state));

  voxa::silenceEmergencyBuzzerState(&state);
  TEST_ASSERT_FALSE(state.sounding);
  TEST_ASSERT_TRUE(state.deliveredForSession);
  TEST_ASSERT_FALSE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 1500U, &state));

  TEST_ASSERT_FALSE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kActive, 2000U, &state));
  TEST_ASSERT_TRUE(voxa::updateEmergencyBuzzerState(
      voxa::SessionLightMode::kOvertimeEmergency, 3000U, &state));
}

}  // namespace

void setUp() {}

void tearDown() {}

int main() {
  UNITY_BEGIN();
  RUN_TEST(validSessionLightPacketParses);
  RUN_TEST(emergencySessionLightPacketParses);
  RUN_TEST(malformedSessionLightPacketsAreRejected);
  RUN_TEST(activeColorMovesThroughGreenYellowOrangeRed);
  RUN_TEST(activeColorInterpolatesBetweenMilestones);
  RUN_TEST(resolvedLightHandlesPauseOvertimeAndOff);
  RUN_TEST(emergencyBuzzerSoundsOnceForExactlyTwoSeconds);
  RUN_TEST(disconnectSilencesWithoutRetriggeringTheSession);
  return UNITY_END();
}
