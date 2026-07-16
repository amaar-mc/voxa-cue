#pragma once

#include <cstddef>
#include <cstdint>

#include "voxa_protocol.hpp"

namespace voxa::ble_transport {

struct ReceivedCommandFrame {
  std::uint8_t bytes[kCommandPacketSize];
  std::size_t reportedLength;
};

bool initialize();

void poll();

bool publishStatus(const std::uint8_t* bytes, std::size_t length);

bool dequeueCommand(ReceivedCommandFrame* output);

}  // namespace voxa::ble_transport
