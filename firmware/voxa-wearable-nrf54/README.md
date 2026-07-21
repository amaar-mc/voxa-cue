# Voxa Cue firmware for XIAO nRF54L15 Sense

This Zephyr firmware ports Voxa Cue firmware `1.3` to the Seeed Studio XIAO
nRF54L15 Sense. It preserves the BLE service, characteristics, packet bytes,
cue patterns, sequence handling, status notifications, session light, and
emergency buzzer behavior defined in [`contracts/ble-v1.md`](../../contracts/ble-v1.md).
The iOS app does not need a board-specific BLE path.

## Wiring

The XIAO and every attached module must share ground. All XIAO GPIO is 3.3 V.

| Function | XIAO pin | nRF54L15 GPIO |
| --- | --- | --- |
| DRV2605L SDA | D4 | P1.10 |
| DRV2605L SCL | D5 | P1.11 |
| RGB red, through a resistor | D6 | P2.08 |
| RGB blue, through a resistor | D7 | P2.07 |
| RGB green, through a resistor | D8 | P2.01 |
| Active-buzzer signal | D9 | P2.04 |

Connect the DRV2605L motor outputs to the ERM. The firmware expects the RGB
LED to be common-cathode and the buzzer to be an active-buzzer module or
driver input. Do not drive a motor, passive speaker, or other high-current load
directly from a XIAO GPIO.

The board overlay disables UART21 on D6/D7 and SPI00 on D8/D9 before claiming
those pins as GPIO. The built-in IMU and microphone are intentionally unused;
the iPhone remains Voxa Cue's only microphone.

## Build and flash

The PlatformIO platform is pinned to the tested Seeed commit in
`platformio.ini`. The ARM compiler is separately pinned to GCC 14.2.1; the
older GCC 8 package selected by Seeed's platform default corrupts Bluetooth
interrupt return state on this target.

```sh
uvx --with pip platformio run -d firmware/voxa-wearable-nrf54
uvx --with pip platformio run -d firmware/voxa-wearable-nrf54 --target upload
```

The upload uses the XIAO's onboard CMSIS-DAP probe. USB serial output is
disabled in the production configuration so battery-only startup does not
depend on a console.

## Runtime behavior

- The peripheral advertises as `Voxa Cue` with the v1 service UUID.
- Commands are accepted only while the status characteristic is subscribed,
  the sequence is fresh, and the DRV2605L responds at I2C address `0x5A`.
- The DRV2605L runs in ERM open-loop real-time playback mode. Playback is
  nonblocking, uses the shared deterministic pattern programs, and probes the
  driver during long cues.
- Missing or disconnected haptic hardware produces the v1 `driver fault`
  rejection. Firmware retries DRV2605L initialization once per second while
  idle, so reconnecting the driver does not require another flash.
- Session-light writes are latest-value-wins. Disconnect or a five-second
  heartbeat timeout turns the LED and buzzer off.
- The emergency buzzer remains independent of DRV2605L readiness.
