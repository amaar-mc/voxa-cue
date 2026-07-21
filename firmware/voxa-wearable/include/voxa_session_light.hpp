#pragma once

#include <cstddef>
#include <cstdint>

#include "voxa_protocol.hpp"

namespace voxa {

enum class SessionLightMode : std::uint8_t {
  kOff = 0U,
  kActive = 1U,
  kPaused = 2U,
  kOvertime = 3U,
  kOvertimeEmergency = 4U,
};

constexpr std::uint32_t kEmergencyBuzzerDurationMilliseconds = 2000U;

struct RgbPinAssignment {
  std::uint8_t red;
  std::uint8_t green;
  std::uint8_t blue;
};

constexpr RgbPinAssignment kNanoSessionLightPins{6U, 8U, 7U};

struct SessionLightCommand {
  std::uint8_t protocolVersion;
  SessionLightMode mode;
  std::uint8_t progressPercent;
};

struct ParseSessionLightResult {
  bool valid;
  SessionLightCommand command;
};

struct RgbColor {
  std::uint8_t red;
  std::uint8_t green;
  std::uint8_t blue;
};

struct EmergencyBuzzerState {
  bool sounding;
  bool deliveredForSession;
  bool hasMode;
  SessionLightMode lastMode;
  std::uint32_t stopAtMilliseconds;
};

ParseSessionLightResult parseSessionLight(const std::uint8_t* bytes,
                                          std::size_t length);

RgbColor activeSessionColor(std::uint8_t progressPercent);

RgbColor resolvedSessionColor(const SessionLightCommand& command,
                              std::uint32_t modeElapsedMilliseconds);

void resetEmergencyBuzzerState(EmergencyBuzzerState* state);

void silenceEmergencyBuzzerState(EmergencyBuzzerState* state);

bool updateEmergencyBuzzerState(SessionLightMode mode,
                                std::uint32_t nowMilliseconds,
                                EmergencyBuzzerState* state);

}  // namespace voxa
