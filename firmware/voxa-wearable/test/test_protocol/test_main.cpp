#include <unity.h>

#include <cstddef>
#include <cstdint>

#include "voxa_protocol.hpp"

namespace {

void validCommandParsesLittleEndianSequence() {
  const std::uint8_t bytes[voxa::kCommandPacketSize]{
      1U, 0x34U, 0x12U, 4U, 2U, 3U};

  const voxa::ParseCommandResult result =
      voxa::parseCommand(bytes, sizeof(bytes));

  TEST_ASSERT_TRUE(result.valid);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::ErrorCode::kNone),
      static_cast<std::uint8_t>(result.error));
  TEST_ASSERT_EQUAL_UINT16(0x1234U, result.command.sequence);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::PatternId::kDeckBehind),
      static_cast<std::uint8_t>(result.command.patternId));
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::Intensity::kStrong),
      static_cast<std::uint8_t>(result.command.intensity));
  TEST_ASSERT_EQUAL_UINT8(3U, result.command.repeatCount);
}

void invalidLengthIsRejectedWithoutReadingBytes() {
  const std::uint8_t bytes[5U]{1U, 1U, 0U, 1U, 1U};

  const voxa::ParseCommandResult shortResult =
      voxa::parseCommand(bytes, sizeof(bytes));
  const voxa::ParseCommandResult nullResult =
      voxa::parseCommand(nullptr, voxa::kCommandPacketSize);

  TEST_ASSERT_FALSE(shortResult.valid);
  TEST_ASSERT_FALSE(nullResult.valid);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::ErrorCode::kInvalidCommand),
      static_cast<std::uint8_t>(shortResult.error));
}

void invalidVersionHasSpecificErrorAndPreservesSequence() {
  const std::uint8_t bytes[voxa::kCommandPacketSize]{
      2U, 0xCDU, 0xABU, 1U, 0U, 1U};

  const voxa::ParseCommandResult result =
      voxa::parseCommand(bytes, sizeof(bytes));

  TEST_ASSERT_FALSE(result.valid);
  TEST_ASSERT_EQUAL_UINT8(
      static_cast<std::uint8_t>(voxa::ErrorCode::kInvalidVersion),
      static_cast<std::uint8_t>(result.error));
  TEST_ASSERT_EQUAL_UINT16(0xABCDU, result.command.sequence);
}

void invalidFieldsAreRejected() {
  const std::uint8_t invalidPattern[voxa::kCommandPacketSize]{
      1U, 1U, 0U, 8U, 0U, 1U};
  const std::uint8_t invalidIntensity[voxa::kCommandPacketSize]{
      1U, 2U, 0U, 1U, 3U, 1U};
  const std::uint8_t zeroRepeats[voxa::kCommandPacketSize]{
      1U, 3U, 0U, 1U, 0U, 0U};
  const std::uint8_t tooManyRepeats[voxa::kCommandPacketSize]{
      1U, 4U, 0U, 1U, 0U, 4U};

  TEST_ASSERT_FALSE(
      voxa::parseCommand(invalidPattern, sizeof(invalidPattern)).valid);
  TEST_ASSERT_FALSE(
      voxa::parseCommand(invalidIntensity, sizeof(invalidIntensity)).valid);
  TEST_ASSERT_FALSE(
      voxa::parseCommand(zeroRepeats, sizeof(zeroRepeats)).valid);
  TEST_ASSERT_FALSE(
      voxa::parseCommand(tooManyRepeats, sizeof(tooManyRepeats)).valid);
}

void statusSerializesToContractBytes() {
  const voxa::StatusPacket status{
      1U, 0xBEEFU, voxa::StatusState::kRejected,
      voxa::ErrorCode::kDriverFault, 1U, 0U};
  std::uint8_t bytes[voxa::kStatusPacketSize]{};

  const bool serialized =
      voxa::serializeStatus(status, bytes, sizeof(bytes));

  const std::uint8_t expected[voxa::kStatusPacketSize]{
      1U, 0xEFU, 0xBEU, 2U, 3U, 1U, 0U};
  TEST_ASSERT_TRUE(serialized);
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, bytes, sizeof(bytes));
  TEST_ASSERT_FALSE(voxa::serializeStatus(status, bytes, sizeof(bytes) - 1U));
}

void untrustedSequenceOnlyReadsCompletePrefix() {
  const std::uint8_t bytes[3U]{9U, 0x78U, 0x56U};

  TEST_ASSERT_EQUAL_UINT16(
      0x5678U, voxa::sequenceFromUntrustedCommand(bytes, sizeof(bytes)));
  TEST_ASSERT_EQUAL_UINT16(
      0U, voxa::sequenceFromUntrustedCommand(bytes, 2U));
  TEST_ASSERT_EQUAL_UINT16(
      0U, voxa::sequenceFromUntrustedCommand(nullptr, 3U));
}

void sequenceTrackerRejectsDuplicatesAndStaleCommands() {
  voxa::SequenceTracker tracker{};
  voxa::clearSequenceTracker(&tracker);

  TEST_ASSERT_TRUE(voxa::canAcceptSequence(tracker, 42U));
  voxa::recordAcceptedSequence(&tracker, 42U);
  voxa::recordCompletedSequence(&tracker, 42U);

  TEST_ASSERT_TRUE(voxa::containsCompletedSequence(tracker, 42U));
  TEST_ASSERT_FALSE(voxa::canAcceptSequence(tracker, 42U));
  TEST_ASSERT_FALSE(voxa::canAcceptSequence(tracker, 41U));
  TEST_ASSERT_TRUE(voxa::canAcceptSequence(tracker, 43U));
}

void sequenceTrackerAcceptsNaturalUint16Wrap() {
  voxa::SequenceTracker tracker{};
  voxa::clearSequenceTracker(&tracker);
  voxa::recordAcceptedSequence(&tracker, 0xFFFFU);

  TEST_ASSERT_TRUE(voxa::canAcceptSequence(tracker, 0U));
  TEST_ASSERT_TRUE(voxa::canAcceptSequence(tracker, 1U));
}

}  // namespace

void setUp() {}

void tearDown() {}

int main() {
  UNITY_BEGIN();
  RUN_TEST(validCommandParsesLittleEndianSequence);
  RUN_TEST(invalidLengthIsRejectedWithoutReadingBytes);
  RUN_TEST(invalidVersionHasSpecificErrorAndPreservesSequence);
  RUN_TEST(invalidFieldsAreRejected);
  RUN_TEST(statusSerializesToContractBytes);
  RUN_TEST(untrustedSequenceOnlyReadsCompletePrefix);
  RUN_TEST(sequenceTrackerRejectsDuplicatesAndStaleCommands);
  RUN_TEST(sequenceTrackerAcceptsNaturalUint16Wrap);
  return UNITY_END();
}
