#include <unity.h>

#include <cstddef>
#include <cstdint>

#include "voxa_patterns.hpp"

namespace {

void assertSegment(const voxa::PatternProgram& program, std::size_t index,
                   bool motorEnabled, std::uint16_t durationMilliseconds) {
  TEST_ASSERT_EQUAL(motorEnabled, program.segments[index].motorEnabled);
  TEST_ASSERT_EQUAL_UINT16(durationMilliseconds,
                           program.segments[index].durationMilliseconds);
}

void allContractPatternsBuild() {
  for (std::uint8_t rawPattern = 1U; rawPattern <= 7U; ++rawPattern) {
    voxa::PatternProgram program{};
    TEST_ASSERT_TRUE(voxa::buildPatternProgram(
        static_cast<voxa::PatternId>(rawPattern), &program));
    TEST_ASSERT_GREATER_THAN_UINT32(0U,
                                    static_cast<std::uint32_t>(program.segmentCount));
    TEST_ASSERT_LESS_OR_EQUAL_UINT32(
        static_cast<std::uint32_t>(voxa::kMaximumPatternSegments),
        static_cast<std::uint32_t>(program.segmentCount));
  }
}

void tooFastIsTwoShortPulses() {
  voxa::PatternProgram program{};

  TEST_ASSERT_TRUE(
      voxa::buildPatternProgram(voxa::PatternId::kTooFast, &program));

  TEST_ASSERT_EQUAL_UINT32(3U,
                           static_cast<std::uint32_t>(program.segmentCount));
  assertSegment(program, 0U, true, 90U);
  assertSegment(program, 1U, false, 80U);
  assertSegment(program, 2U, true, 90U);
}

void fillerBurstIsThreeShortPulses() {
  voxa::PatternProgram program{};

  TEST_ASSERT_TRUE(
      voxa::buildPatternProgram(voxa::PatternId::kFillerBurst, &program));

  TEST_ASSERT_EQUAL_UINT32(5U,
                           static_cast<std::uint32_t>(program.segmentCount));
  assertSegment(program, 0U, true, 70U);
  assertSegment(program, 1U, false, 70U);
  assertSegment(program, 2U, true, 70U);
  assertSegment(program, 3U, false, 70U);
  assertSegment(program, 4U, true, 70U);
}

void deckBehindIsLongShortLong() {
  voxa::PatternProgram program{};

  TEST_ASSERT_TRUE(
      voxa::buildPatternProgram(voxa::PatternId::kDeckBehind, &program));

  assertSegment(program, 0U, true, 300U);
  assertSegment(program, 1U, false, 100U);
  assertSegment(program, 2U, true, 80U);
  assertSegment(program, 3U, false, 100U);
  assertSegment(program, 4U, true, 300U);
}

void intensityMapsToIncreasingConservativeAmplitudes() {
  const std::uint8_t soft =
      voxa::amplitudeForIntensity(voxa::Intensity::kSoft);
  const std::uint8_t medium =
      voxa::amplitudeForIntensity(voxa::Intensity::kMedium);
  const std::uint8_t strong =
      voxa::amplitudeForIntensity(voxa::Intensity::kStrong);

  TEST_ASSERT_GREATER_THAN_UINT8(0U, soft);
  TEST_ASSERT_GREATER_THAN_UINT8(soft, medium);
  TEST_ASSERT_GREATER_THAN_UINT8(medium, strong);
  TEST_ASSERT_LESS_OR_EQUAL_UINT8(127U, strong);
}

void repeatDurationIncludesOnlyInterRepeatGaps() {
  voxa::PatternProgram program{};
  TEST_ASSERT_TRUE(
      voxa::buildPatternProgram(voxa::PatternId::kTime75Percent, &program));

  TEST_ASSERT_EQUAL_UINT32(120U, voxa::durationForProgram(program, 1U));
  TEST_ASSERT_EQUAL_UINT32(400U, voxa::durationForProgram(program, 2U));
  TEST_ASSERT_EQUAL_UINT32(680U, voxa::durationForProgram(program, 3U));
  TEST_ASSERT_EQUAL_UINT32(0U, voxa::durationForProgram(program, 0U));
  TEST_ASSERT_EQUAL_UINT32(0U, voxa::durationForProgram(program, 4U));
}

void unknownPatternAndNullOutputFail() {
  voxa::PatternProgram program{};

  TEST_ASSERT_FALSE(voxa::buildPatternProgram(
      static_cast<voxa::PatternId>(0U), &program));
  TEST_ASSERT_FALSE(
      voxa::buildPatternProgram(voxa::PatternId::kTooFast, nullptr));
}

}  // namespace

void setUp() {}

void tearDown() {}

int main() {
  UNITY_BEGIN();
  RUN_TEST(allContractPatternsBuild);
  RUN_TEST(tooFastIsTwoShortPulses);
  RUN_TEST(fillerBurstIsThreeShortPulses);
  RUN_TEST(deckBehindIsLongShortLong);
  RUN_TEST(intensityMapsToIncreasingConservativeAmplitudes);
  RUN_TEST(repeatDurationIncludesOnlyInterRepeatGaps);
  RUN_TEST(unknownPatternAndNullOutputFail);
  return UNITY_END();
}
