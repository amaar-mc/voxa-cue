#pragma once

#include <cstddef>
#include <cstdint>

#include "voxa_protocol.hpp"

namespace voxa {

constexpr std::size_t kMaximumPatternSegments = 9U;

struct PatternSegment {
  std::uint8_t amplitudePercent;
  std::uint16_t durationMilliseconds;
};

struct PatternProgram {
  PatternSegment segments[kMaximumPatternSegments];
  std::size_t segmentCount;
  std::uint16_t repeatGapMilliseconds;
};

bool buildPatternProgram(PatternId patternId, PatternProgram* output);

std::uint8_t amplitudeForIntensity(Intensity intensity);

std::uint8_t scaledAmplitudeForIntensity(Intensity intensity,
                                         std::uint8_t amplitudePercent);

std::uint32_t durationForProgram(const PatternProgram& program,
                                 std::uint8_t repeatCount);

}  // namespace voxa
