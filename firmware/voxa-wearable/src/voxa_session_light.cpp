#include "voxa_session_light.hpp"

namespace voxa {
namespace {

constexpr RgbColor kOffColor{0U, 0U, 0U};
constexpr RgbColor kGreenColor{0U, 255U, 0U};
constexpr RgbColor kYellowColor{255U, 255U, 0U};
constexpr RgbColor kOrangeColor{255U, 128U, 0U};
constexpr RgbColor kRedColor{255U, 0U, 0U};

bool isSessionLightModeValid(std::uint8_t value) {
  return value <=
         static_cast<std::uint8_t>(SessionLightMode::kOvertimeEmergency);
}

bool timeReached(std::uint32_t nowMilliseconds,
                 std::uint32_t deadlineMilliseconds) {
  return static_cast<std::int32_t>(nowMilliseconds - deadlineMilliseconds) >=
         0;
}

std::uint8_t interpolateChannel(std::uint8_t start, std::uint8_t end,
                                std::uint8_t numerator,
                                std::uint8_t denominator) {
  const std::int32_t delta = static_cast<std::int32_t>(end) -
                             static_cast<std::int32_t>(start);
  const std::int32_t scaled = delta * numerator;
  const std::int32_t rounding =
      scaled >= 0 ? denominator / 2U : -static_cast<std::int32_t>(denominator / 2U);
  return static_cast<std::uint8_t>(
      static_cast<std::int32_t>(start) +
      (scaled + rounding) / static_cast<std::int32_t>(denominator));
}

RgbColor interpolateColor(const RgbColor& start, const RgbColor& end,
                          std::uint8_t numerator, std::uint8_t denominator) {
  return RgbColor{
      interpolateChannel(start.red, end.red, numerator, denominator),
      interpolateChannel(start.green, end.green, numerator, denominator),
      interpolateChannel(start.blue, end.blue, numerator, denominator)};
}

}  // namespace

ParseSessionLightResult parseSessionLight(const std::uint8_t* bytes,
                                          std::size_t length) {
  const SessionLightCommand empty{
      0U, SessionLightMode::kOff, 0U};
  if (bytes == nullptr || length != kSessionLightPacketSize) {
    return ParseSessionLightResult{false, empty};
  }
  if (bytes[0] != kProtocolVersion || !isSessionLightModeValid(bytes[1]) ||
      bytes[2] > 100U) {
    return ParseSessionLightResult{false, empty};
  }
  return ParseSessionLightResult{
      true,
      SessionLightCommand{bytes[0], static_cast<SessionLightMode>(bytes[1]),
                          bytes[2]}};
}

RgbColor activeSessionColor(std::uint8_t progressPercent) {
  const std::uint8_t bounded = progressPercent > 100U ? 100U : progressPercent;
  if (bounded <= 50U) {
    return interpolateColor(kGreenColor, kYellowColor, bounded, 50U);
  }
  if (bounded <= 75U) {
    return interpolateColor(kYellowColor, kOrangeColor,
                            static_cast<std::uint8_t>(bounded - 50U), 25U);
  }
  return interpolateColor(kOrangeColor, kRedColor,
                          static_cast<std::uint8_t>(bounded - 75U), 25U);
}

RgbColor resolvedSessionColor(const SessionLightCommand& command,
                              std::uint32_t modeElapsedMilliseconds) {
  switch (command.mode) {
    case SessionLightMode::kOff:
      return kOffColor;
    case SessionLightMode::kActive:
    case SessionLightMode::kPaused:
      return activeSessionColor(command.progressPercent);
    case SessionLightMode::kOvertime:
    case SessionLightMode::kOvertimeEmergency:
      return modeElapsedMilliseconds % 1000U < 500U ? kRedColor : kOffColor;
  }
  return kOffColor;
}

void resetEmergencyBuzzerState(EmergencyBuzzerState* state) {
  if (state == nullptr) {
    return;
  }
  *state = EmergencyBuzzerState{
      false, false, false, SessionLightMode::kOff, 0U};
}

void silenceEmergencyBuzzerState(EmergencyBuzzerState* state) {
  if (state == nullptr) {
    return;
  }
  state->sounding = false;
}

bool updateEmergencyBuzzerState(SessionLightMode mode,
                                std::uint32_t nowMilliseconds,
                                EmergencyBuzzerState* state) {
  if (state == nullptr) {
    return false;
  }

  if (mode == SessionLightMode::kOff) {
    resetEmergencyBuzzerState(state);
    state->hasMode = true;
    return false;
  }

  if (mode == SessionLightMode::kActive &&
      (!state->hasMode || state->lastMode != SessionLightMode::kActive)) {
    state->sounding = false;
    state->deliveredForSession = false;
  }

  if (mode == SessionLightMode::kOvertimeEmergency &&
      !state->deliveredForSession) {
    state->sounding = true;
    state->deliveredForSession = true;
    state->stopAtMilliseconds =
        nowMilliseconds + kEmergencyBuzzerDurationMilliseconds;
  }

  if (state->sounding &&
      timeReached(nowMilliseconds, state->stopAtMilliseconds)) {
    state->sounding = false;
  }

  state->hasMode = true;
  state->lastMode = mode;
  return state->sounding;
}

}  // namespace voxa
