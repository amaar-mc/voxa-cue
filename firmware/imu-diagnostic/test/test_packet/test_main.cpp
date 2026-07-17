#include <unity.h>

#include <cstddef>
#include <cstdint>

#include "imu_packet.hpp"

void setUp() {}
void tearDown() {}

void test_serializes_twenty_byte_motion_sample() {
  const voxa::imu::MotionSample sample{0x1234U, 0x78563412U, 1.25F, -0.5F,
                                       0.0F,     12.3F,      -45.6F, 3276.7F,
                                       true};
  std::uint8_t bytes[voxa::imu::kSamplePacketSize]{};

  TEST_ASSERT_TRUE(
      voxa::imu::serializeSample(sample, bytes, sizeof(bytes)));
  TEST_ASSERT_EQUAL_UINT8(1U, bytes[0]);
  TEST_ASSERT_EQUAL_UINT8(1U, bytes[1]);
  TEST_ASSERT_EQUAL_UINT8(0x34U, bytes[2]);
  TEST_ASSERT_EQUAL_UINT8(0x12U, bytes[3]);
  TEST_ASSERT_EQUAL_UINT8(0x12U, bytes[4]);
  TEST_ASSERT_EQUAL_UINT8(0x34U, bytes[5]);
  TEST_ASSERT_EQUAL_UINT8(0x56U, bytes[6]);
  TEST_ASSERT_EQUAL_UINT8(0x78U, bytes[7]);
  TEST_ASSERT_EQUAL_INT16(1250,
                          static_cast<std::int16_t>(bytes[8] | bytes[9] << 8U));
  TEST_ASSERT_EQUAL_INT16(
      -500, static_cast<std::int16_t>(bytes[10] | bytes[11] << 8U));
  TEST_ASSERT_EQUAL_INT16(
      32767, static_cast<std::int16_t>(bytes[18] | bytes[19] << 8U));
}

void test_rejects_wrong_sample_buffer_size() {
  const voxa::imu::MotionSample sample{};
  std::uint8_t bytes[voxa::imu::kSamplePacketSize - 1U]{};
  TEST_ASSERT_FALSE(
      voxa::imu::serializeSample(sample, bytes, sizeof(bytes)));
}

void test_serializes_sensor_info() {
  const voxa::imu::SensorInfo info{voxa::imu::SensorKind::kMpu6050, 0x68U,
                                   voxa::imu::SensorState::kReady, 25U};
  std::uint8_t bytes[voxa::imu::kInfoPacketSize]{};

  TEST_ASSERT_TRUE(voxa::imu::serializeInfo(info, bytes, sizeof(bytes)));
  const std::uint8_t expected[voxa::imu::kInfoPacketSize] = {
      1U, 1U, 0x68U, 0U, 25U, 0U, 1U, 0U};
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, bytes, sizeof(bytes));
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_serializes_twenty_byte_motion_sample);
  RUN_TEST(test_rejects_wrong_sample_buffer_size);
  RUN_TEST(test_serializes_sensor_info);
  return UNITY_END();
}
