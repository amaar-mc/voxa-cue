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
};

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

ParseSessionLightResult parseSessionLight(const std::uint8_t* bytes,
                                          std::size_t length);

RgbColor activeSessionColor(std::uint8_t progressPercent);

RgbColor resolvedSessionColor(const SessionLightCommand& command,
                              std::uint32_t modeElapsedMilliseconds);

}  // namespace voxa
