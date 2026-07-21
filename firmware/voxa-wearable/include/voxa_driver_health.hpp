#pragma once

#include <cstdint>

namespace voxa {

constexpr std::uint32_t kDriverRecoveryIntervalMilliseconds = 1000U;

struct DriverHealthState {
  bool ready;
  std::uint32_t nextRecoveryAttemptMilliseconds;
};

inline bool driverRecoveryIsDue(const DriverHealthState& state,
                                std::uint32_t nowMilliseconds) {
  return !state.ready &&
         static_cast<std::int32_t>(
             nowMilliseconds - state.nextRecoveryAttemptMilliseconds) >= 0;
}

inline void recordDriverFault(std::uint32_t nowMilliseconds,
                              DriverHealthState* state) {
  state->ready = false;
  state->nextRecoveryAttemptMilliseconds =
      nowMilliseconds + kDriverRecoveryIntervalMilliseconds;
}

inline void recordDriverRecovery(bool succeeded,
                                 std::uint32_t nowMilliseconds,
                                 DriverHealthState* state) {
  state->ready = succeeded;
  state->nextRecoveryAttemptMilliseconds =
      nowMilliseconds + kDriverRecoveryIntervalMilliseconds;
}

}  // namespace voxa
