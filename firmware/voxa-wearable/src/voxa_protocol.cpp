#include "voxa_protocol.hpp"

namespace voxa {
namespace {

bool isPatternIdValid(std::uint8_t value) {
  return value >= static_cast<std::uint8_t>(PatternId::kTooFast) &&
         value <= static_cast<std::uint8_t>(PatternId::kDeadlineHold);
}

bool isIntensityValid(std::uint8_t value) {
  return value <= static_cast<std::uint8_t>(Intensity::kStrong);
}

CommandPacket emptyCommand() {
  return CommandPacket{0U, 0U, PatternId::kTooFast, Intensity::kSoft, 0U};
}

}  // namespace

ParseCommandResult parseCommand(const std::uint8_t* bytes,
                                std::size_t length) {
  if (bytes == nullptr || length != kCommandPacketSize) {
    return ParseCommandResult{false, ErrorCode::kInvalidCommand,
                              emptyCommand()};
  }

  const std::uint16_t sequence =
      static_cast<std::uint16_t>(bytes[1]) |
      static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[2]) << 8U);

  if (bytes[0] != kProtocolVersion) {
    return ParseCommandResult{
        false, ErrorCode::kInvalidVersion,
        CommandPacket{bytes[0], sequence, PatternId::kTooFast,
                      Intensity::kSoft, 0U}};
  }

  if (!isPatternIdValid(bytes[3]) || !isIntensityValid(bytes[4]) ||
      bytes[5] < 1U || bytes[5] > 3U) {
    return ParseCommandResult{
        false, ErrorCode::kInvalidCommand,
        CommandPacket{bytes[0], sequence, PatternId::kTooFast,
                      Intensity::kSoft, bytes[5]}};
  }

  return ParseCommandResult{
      true,
      ErrorCode::kNone,
      CommandPacket{bytes[0], sequence, static_cast<PatternId>(bytes[3]),
                    static_cast<Intensity>(bytes[4]), bytes[5]}};
}

bool serializeStatus(const StatusPacket& status, std::uint8_t* output,
                     std::size_t outputLength) {
  if (output == nullptr || outputLength != kStatusPacketSize) {
    return false;
  }

  output[0] = status.protocolVersion;
  output[1] = static_cast<std::uint8_t>(status.sequence & 0x00FFU);
  output[2] = static_cast<std::uint8_t>((status.sequence >> 8U) & 0x00FFU);
  output[3] = static_cast<std::uint8_t>(status.state);
  output[4] = static_cast<std::uint8_t>(status.error);
  output[5] = status.firmwareMajor;
  output[6] = status.firmwareMinor;
  return true;
}

std::uint16_t sequenceFromUntrustedCommand(const std::uint8_t* bytes,
                                           std::size_t length) {
  if (bytes == nullptr || length < 3U) {
    return 0U;
  }

  return static_cast<std::uint16_t>(bytes[1]) |
         static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[2])
                                    << 8U);
}

void clearSequenceTracker(SequenceTracker* tracker) {
  if (tracker == nullptr) {
    return;
  }

  tracker->initialized = false;
  tracker->mostRecentAccepted = 0U;
  tracker->hasCompleted = false;
  tracker->mostRecentCompleted = 0U;
}

bool canAcceptSequence(const SequenceTracker& tracker, std::uint16_t sequence) {
  if (!tracker.initialized) {
    return true;
  }

  const std::uint16_t distance =
      static_cast<std::uint16_t>(sequence - tracker.mostRecentAccepted);
  return distance != 0U && distance < 0x8000U;
}

void recordAcceptedSequence(SequenceTracker* tracker, std::uint16_t sequence) {
  if (tracker == nullptr) {
    return;
  }

  tracker->initialized = true;
  tracker->mostRecentAccepted = sequence;
}

void recordCompletedSequence(SequenceTracker* tracker, std::uint16_t sequence) {
  if (tracker == nullptr) {
    return;
  }

  tracker->hasCompleted = true;
  tracker->mostRecentCompleted = sequence;
}

bool containsCompletedSequence(const SequenceTracker& tracker,
                               std::uint16_t sequence) {
  return tracker.hasCompleted && tracker.mostRecentCompleted == sequence;
}

}  // namespace voxa
