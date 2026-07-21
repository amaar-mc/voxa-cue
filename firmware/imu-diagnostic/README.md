# Voxa IMU diagnostic firmware

This is a standalone lab build. It does not modify or share code with the Voxa
Cue haptic firmware. Flashing it temporarily replaces the sketch running on the
Nano 33 IoT; the production wearable firmware can be flashed back afterward.

## Sensor and wiring

The Nano 33 IoT's onboard LSM6DS3 is the default sensor. It is already connected
to the board's I2C bus at `0x6A`, so no external IMU wiring is required for the
gesture dataset recorder. The diagnostic configures its accelerometer for
±4 g so ordinary fast hand gestures do not clip at the default ±2 g range.

The diagnostic can also inspect a supported external I2C sensor. For that
optional setup, use the pins printed on the Nano 33 IoT:

| External IMU | Nano 33 IoT |
| --- | --- |
| `VCC` | `3V3` |
| `GND` | `GND` |
| `SDA` | `A4 / SDA` |
| `SCL` | `A5 / SCL` |

Do not power an unknown sensor board from `5V`. The Nano 33 IoT is a 3.3 V
board and its I/O is not 5 V tolerant.

## Supported sensors

The adapter currently identifies and reads:

- MPU-6050-compatible devices at `0x68` or `0x69`
- LSM6DS3 / LSM6DSL / LSM6DSO-family devices at `0x6A` or `0x6B`

On every boot, the serial console scans the complete I2C bus. An unknown device
is reported as unsupported with its address instead of producing fake motion
data. Add its register map to `src/imu_sensor.cpp` once the exact chip is known.

## Build, flash, and inspect

From the repository root:

```sh
uvx --with pip platformio test -e native -d firmware/imu-diagnostic
uvx --with pip platformio run -e nano_33_iot -d firmware/imu-diagnostic
uvx --with pip platformio run -e nano_33_iot -d firmware/imu-diagnostic \
  --target upload --upload-port /dev/cu.usbmodem1101
uvx --with pip platformio device monitor \
  --port /dev/cu.usbmodem1101 --baud 115200
```

The serial output lists every responding I2C address, then the detected sensor
kind and state. The BLE device advertises as `Voxa IMU Lab` and sends 50 samples
per second to the diagnostic tools. Use `ml/gesture-classifier/recorder` for
labeled trials and `tools/imu-debug` for live engineering inspection.

To restore the wearable firmware afterward:

```sh
uvx --with pip platformio run -e nano_33_iot -d firmware/voxa-wearable \
  --target upload --upload-port /dev/cu.usbmodem1101
```

## BLE packet

The sample notification is exactly 20 bytes so it fits the default BLE ATT
payload. Integers are little-endian.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | `uint8` | Protocol version (`1`) |
| 1 | `uint8` | Sensor healthy (`1`); a read fault emits one sequenced `0` packet |
| 2–3 | `uint16` | Sequence |
| 4–7 | `uint32` | Milliseconds since boot |
| 8–13 | `int16 × 3` | X/Y/Z acceleration in milli-g |
| 14–19 | `int16 × 3` | X/Y/Z angular velocity in 0.1 °/s |

Service: `7A3E1001-7C7B-4E25-9A5A-8D7C9F1A0001`  
Sample: `7A3E1002-7C7B-4E25-9A5A-8D7C9F1A0001`  
Sensor info: `7A3E1003-7C7B-4E25-9A5A-8D7C9F1A0001`
