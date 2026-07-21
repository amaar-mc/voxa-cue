#include <unity.h>

#include <cstdint>

#include "voxa_driver_health.hpp"

namespace {

void aFaultDisablesPlaybackUntilTheRecoveryDeadline() {
  voxa::DriverHealthState state{true, 0U};

  voxa::recordDriverFault(500U, &state);

  TEST_ASSERT_FALSE(state.ready);
  TEST_ASSERT_FALSE(voxa::driverRecoveryIsDue(state, 1499U));
  TEST_ASSERT_TRUE(voxa::driverRecoveryIsDue(state, 1500U));
}

void failedRecoverySchedulesAnotherBoundedAttempt() {
  voxa::DriverHealthState state{false, 1000U};

  voxa::recordDriverRecovery(false, 1000U, &state);

  TEST_ASSERT_FALSE(state.ready);
  TEST_ASSERT_FALSE(voxa::driverRecoveryIsDue(state, 1999U));
  TEST_ASSERT_TRUE(voxa::driverRecoveryIsDue(state, 2000U));
}

void successfulRecoveryRestoresCommandReadiness() {
  voxa::DriverHealthState state{false, 1000U};

  voxa::recordDriverRecovery(true, 1000U, &state);

  TEST_ASSERT_TRUE(state.ready);
  TEST_ASSERT_FALSE(voxa::driverRecoveryIsDue(state, 5000U));
}

void recoveryDeadlineHandlesMillisecondRollover() {
  voxa::DriverHealthState state{false, 0x00000020U};

  TEST_ASSERT_FALSE(voxa::driverRecoveryIsDue(state, 0x0000001FU));
  TEST_ASSERT_TRUE(voxa::driverRecoveryIsDue(state, 0x00000020U));
}

}  // namespace

int main(int argc, char** argv) {
  (void)argc;
  (void)argv;
  UNITY_BEGIN();
  RUN_TEST(aFaultDisablesPlaybackUntilTheRecoveryDeadline);
  RUN_TEST(failedRecoverySchedulesAnotherBoundedAttempt);
  RUN_TEST(successfulRecoveryRestoresCommandReadiness);
  RUN_TEST(recoveryDeadlineHandlesMillisecondRollover);
  return UNITY_END();
}
