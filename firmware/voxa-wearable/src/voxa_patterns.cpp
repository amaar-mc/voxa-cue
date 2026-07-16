#include "voxa_patterns.hpp"

namespace voxa {
namespace {

constexpr std::uint16_t kRepeatGapMilliseconds = 160U;

void clearProgram(PatternProgram* output) {
  for (std::size_t index = 0U; index < kMaximumPatternSegments; ++index) {
    output->segments[index] = PatternSegment{false, 0U};
  }
  output->segmentCount = 0U;
  output->repeatGapMilliseconds = kRepeatGapMilliseconds;
}

void setSegment(PatternProgram* output, std::size_t index, bool motorEnabled,
                std::uint16_t durationMilliseconds) {
  output->segments[index] =
      PatternSegment{motorEnabled, durationMilliseconds};
}

}  // namespace

bool buildPatternProgram(PatternId patternId, PatternProgram* output) {
  if (output == nullptr) {
    return false;
  }
  clearProgram(output);

  switch (patternId) {
    case PatternId::kTooFast:
      setSegment(output, 0U, true, 90U);
      setSegment(output, 1U, false, 80U);
      setSegment(output, 2U, true, 90U);
      output->segmentCount = 3U;
      return true;
    case PatternId::kTooSlow:
      setSegment(output, 0U, true, 350U);
      output->segmentCount = 1U;
      return true;
    case PatternId::kFillerBurst:
      setSegment(output, 0U, true, 70U);
      setSegment(output, 1U, false, 70U);
      setSegment(output, 2U, true, 70U);
      setSegment(output, 3U, false, 70U);
      setSegment(output, 4U, true, 70U);
      output->segmentCount = 5U;
      return true;
    case PatternId::kDeckBehind:
      setSegment(output, 0U, true, 300U);
      setSegment(output, 1U, false, 100U);
      setSegment(output, 2U, true, 80U);
      setSegment(output, 3U, false, 100U);
      setSegment(output, 4U, true, 300U);
      output->segmentCount = 5U;
      return true;
    case PatternId::kTime75Percent:
      setSegment(output, 0U, true, 120U);
      output->segmentCount = 1U;
      return true;
    case PatternId::kTime90Percent:
      setSegment(output, 0U, true, 150U);
      setSegment(output, 1U, false, 100U);
      setSegment(output, 2U, true, 150U);
      output->segmentCount = 3U;
      return true;
    case PatternId::kTime100Percent:
      setSegment(output, 0U, true, 220U);
      setSegment(output, 1U, false, 90U);
      setSegment(output, 2U, true, 220U);
      setSegment(output, 3U, false, 90U);
      setSegment(output, 4U, true, 220U);
      output->segmentCount = 5U;
      return true;
  }

  return false;
}

std::uint8_t amplitudeForIntensity(Intensity intensity) {
  switch (intensity) {
    case Intensity::kSoft:
      return 45U;
    case Intensity::kMedium:
      return 75U;
    case Intensity::kStrong:
      return 105U;
  }
  return 0U;
}

std::uint32_t durationForProgram(const PatternProgram& program,
                                 std::uint8_t repeatCount) {
  if (repeatCount < 1U || repeatCount > 3U || program.segmentCount == 0U ||
      program.segmentCount > kMaximumPatternSegments) {
    return 0U;
  }

  std::uint32_t onePassMilliseconds = 0U;
  for (std::size_t index = 0U; index < program.segmentCount; ++index) {
    onePassMilliseconds += program.segments[index].durationMilliseconds;
  }

  return onePassMilliseconds * repeatCount +
         static_cast<std::uint32_t>(program.repeatGapMilliseconds) *
             static_cast<std::uint32_t>(repeatCount - 1U);
}

}  // namespace voxa

