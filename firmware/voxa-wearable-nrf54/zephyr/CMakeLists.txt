cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(voxa_wearable_nrf54)

set(VOXA_SHARED_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../voxa-wearable)

target_include_directories(app PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../include
  ${VOXA_SHARED_DIR}/include
)

target_sources(app PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/../src/main.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../src/voxa_drv2605l.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../src/voxa_ble_transport_zephyr.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../src/voxa_patterns_shared.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../src/voxa_protocol_shared.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/../src/voxa_session_light_shared.cpp
)

target_compile_options(app PRIVATE
  $<$<COMPILE_LANGUAGE:CXX>:-Wall -Wextra -Werror -Wno-missing-field-initializers>
)
