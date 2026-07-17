#include "voxa_patterns.hpp"

namespace voxa {
namespace {

constexpr std::uint16_t kRepeatGapMilliseconds = 160U;

void clearProgram(PatternProgram* output) {
  for (std::size_t index = 0U; index < kMaximumPatternSegments; ++index) {
    output->segments[index] = PatternSegment{0U, 0U};
  }
  output->segmentCount = 0U;
  output->repeatGapMilliseconds = kRepeatGapMilliseconds;
}

void setSegment(PatternProgram* output, std::size_t index,
                std::uint8_t amplitudePercent,
                std::uint16_t durationMilliseconds) {
  output->segments[index] =
      PatternSegment{amplitudePercent, durationMilliseconds};
}

}  // namespace

bool buildPatternProgram(PatternId patternId, PatternProgram* output) {
  if (output == nullptr) {
    return false;
  }
  clearProgram(output);

  switch (patternId) {
    case PatternId::kTooFast:
      setSegment(output, 0U, 100U, 90U);
      setSegment(output, 1U, 0U, 80U);
      setSegment(output, 2U, 100U, 90U);
      output->segmentCount = 3U;
      return true;
    case PatternId::kTooSlow:
      setSegment(output, 0U, 100U, 350U);
      output->segmentCount = 1U;
      return true;
    case PatternId::kFillerBurst:
      setSegment(output, 0U, 100U, 70U);
      setSegment(output, 1U, 0U, 70U);
      setSegment(output, 2U, 100U, 70U);
      setSegment(output, 3U, 0U, 70U);
      setSegment(output, 4U, 100U, 70U);
      output->segmentCount = 5U;
      return true;
    case PatternId::kDeckBehind:
      setSegment(output, 0U, 100U, 300U);
      setSegment(output, 1U, 0U, 100U);
      setSegment(output, 2U, 100U, 80U);
      setSegment(output, 3U, 0U, 100U);
      setSegment(output, 4U, 100U, 300U);
      output->segmentCount = 5U;
      return true;
    case PatternId::kTime75Percent:
      setSegment(output, 0U, 100U, 120U);
      output->segmentCount = 1U;
      return true;
    case PatternId::kTime90Percent:
      setSegment(output, 0U, 100U, 150U);
      setSegment(output, 1U, 0U, 100U);
      setSegment(output, 2U, 100U, 150U);
      output->segmentCount = 3U;
      return true;
    case PatternId::kTime100Percent:
      setSegment(output, 0U, 100U, 220U);
      setSegment(output, 1U, 0U, 90U);
      setSegment(output, 2U, 100U, 220U);
      setSegment(output, 3U, 0U, 90U);
      setSegment(output, 4U, 100U, 220U);
      output->segmentCount = 5U;
      return true;
    case PatternId::kCalmWave: {
      constexpr std::uint8_t kEnvelope[] = {40U, 55U, 70U, 85U, 100U,
                                            85U, 70U, 55U, 40U};
      for (std::size_t index = 0U; index < 9U; ++index) {
        setSegment(output, index, kEnvelope[index], 90U);
      }
      output->segmentCount = 9U;
      return true;
    }
    case PatternId::kDeadlineHold:
      setSegment(output, 0U, 100U, 1200U);
      output->segmentCount = 1U;
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

std::uint8_t scaledAmplitudeForIntensity(
    Intensity intensity, std::uint8_t amplitudePercent) {
  const std::uint16_t boundedPercent =
      amplitudePercent > 100U ? 100U : amplitudePercent;
  return static_cast<std::uint8_t>(
      static_cast<std::uint16_t>(amplitudeForIntensity(intensity)) *
      boundedPercent / 100U);
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
