#pragma once

#include <cstddef>
#include <cstdint>

namespace voxa {

constexpr std::uint8_t kProtocolVersion = 1U;
constexpr std::uint8_t kFirmwareMajor = 1U;
constexpr std::uint8_t kFirmwareMinor = 0U;
constexpr std::size_t kCommandPacketSize = 6U;
constexpr std::size_t kStatusPacketSize = 7U;

constexpr char kDeviceName[] = "Voxa Cue";
constexpr char kServiceUuid[] = "6F2A0001-7C93-4A58-A9D4-3C52BBD1F110";
constexpr char kCommandCharacteristicUuid[] =
    "6F2A0002-7C93-4A58-A9D4-3C52BBD1F110";
constexpr char kStatusCharacteristicUuid[] =
    "6F2A0003-7C93-4A58-A9D4-3C52BBD1F110";

enum class PatternId : std::uint8_t {
  kTooFast = 1U,
  kTooSlow = 2U,
  kFillerBurst = 3U,
  kDeckBehind = 4U,
  kTime75Percent = 5U,
  kTime90Percent = 6U,
  kTime100Percent = 7U,
};

enum class Intensity : std::uint8_t {
  kSoft = 0U,
  kMedium = 1U,
  kStrong = 2U,
};

enum class StatusState : std::uint8_t {
  kAccepted = 0U,
  kCompleted = 1U,
  kRejected = 2U,
};

enum class ErrorCode : std::uint8_t {
  kNone = 0U,
  kInvalidVersion = 1U,
  kInvalidCommand = 2U,
  kDriverFault = 3U,
};

struct CommandPacket {
  std::uint8_t protocolVersion;
  std::uint16_t sequence;
  PatternId patternId;
  Intensity intensity;
  std::uint8_t repeatCount;
};

struct StatusPacket {
  std::uint8_t protocolVersion;
  std::uint16_t sequence;
  StatusState state;
  ErrorCode error;
  std::uint8_t firmwareMajor;
  std::uint8_t firmwareMinor;
};

struct ParseCommandResult {
  bool valid;
  ErrorCode error;
  CommandPacket command;
};

struct SequenceTracker {
  bool initialized;
  std::uint16_t mostRecentAccepted;
  bool hasCompleted;
  std::uint16_t mostRecentCompleted;
};

ParseCommandResult parseCommand(const std::uint8_t* bytes, std::size_t length);

bool serializeStatus(const StatusPacket& status, std::uint8_t* output,
                     std::size_t outputLength);

std::uint16_t sequenceFromUntrustedCommand(const std::uint8_t* bytes,
                                           std::size_t length);

void clearSequenceTracker(SequenceTracker* tracker);

bool canAcceptSequence(const SequenceTracker& tracker, std::uint16_t sequence);

void recordAcceptedSequence(SequenceTracker* tracker, std::uint16_t sequence);

void recordCompletedSequence(SequenceTracker* tracker, std::uint16_t sequence);

bool containsCompletedSequence(const SequenceTracker& tracker,
                               std::uint16_t sequence);

}  // namespace voxa
