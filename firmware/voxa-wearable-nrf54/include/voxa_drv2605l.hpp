#pragma once

#include <cstdint>

namespace voxa::drv2605l {

bool initialize();

bool isPresent();

bool setRealtimeValue(std::uint8_t value);

}  // namespace voxa::drv2605l

