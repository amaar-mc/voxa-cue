# Voxa Cue wearable firmware

Firmware v1.0 turns the Arduino Nano ESP32 into a BLE peripheral that accepts
versioned, semantic haptic commands from the Voxa Cue iPhone app. The Nano
drives a 3 V LRA through a DRV2605L in real-time playback mode; the main loop
never blocks for the length of a vibration.

The wire contract is defined in [`../../contracts/ble-v1.md`](../../contracts/ble-v1.md).
The implementation rejects malformed packets, unsupported protocol versions,
busy commands, stale or duplicate sequence numbers, and commands received when
the motor driver is unavailable. Every valid command reports `accepted`, then
`completed`; a driver failure reports `rejected / driver fault`.

## Hardware

- Arduino Nano ESP32
- DRV2605L breakout at I2C address `0x5A`
- 3 V LRA coin vibration motor
- USB-C cable for the bench prototype

Wire with all power disconnected:

| Nano ESP32 | DRV2605L breakout | Purpose |
| --- | --- | --- |
| `3V3` | `VIN` | Driver power for the bench prototype |
| `GND` | `GND` | Shared ground |
| `A4` | `SDA` | I2C data |
| `A5` | `SCL` | I2C clock |
| — | `OUT+` / `OUT-` | LRA motor leads; polarity is not significant |

Do not connect the motor directly to a Nano GPIO or directly across 3V3/GND.
It must connect only to the DRV2605L output. Confirm that the particular
breakout accepts 3.3 V on `VIN`; boards with a different input requirement need
the power arrangement specified by their manufacturer. A wearable battery
requires a protected cell, charging circuit, and appropriate regulation—do not
connect a bare LiPo as a substitute for USB power.

## Build, test, and flash

PlatformIO is invoked through `uvx`, so no global installation is required.
`--with pip` is required because PlatformIO installs Python helpers for the
ESP32 flashing toolchain on its first run:

```sh
cd firmware/voxa-wearable
uvx --with pip platformio test -e native
uvx --with pip platformio run -e nano_esp32
uvx --with pip platformio run -e nano_esp32 --target upload
uvx --with pip platformio device monitor --baud 115200
```

If PlatformIO cannot find the upload port, list ports with
`uvx --with pip platformio device list`, then pass the result explicitly with
`--upload-port /dev/cu.usbmodem...`.

On startup the serial monitor prints either `Voxa Cue firmware 1.0 ready` or a
DRV2605L detection failure. A missing driver does not crash BLE; commands are
rejected with the protocol's `driver fault` error.

## BLE smoke test

Use a BLE inspector such as LightBlue while the iPhone app is unavailable:

1. Connect to `Voxa Cue`.
2. Open service `6F2A0001-7C93-4A58-A9D4-3C52BBD1F110`.
3. Subscribe to status characteristic
   `6F2A0003-7C93-4A58-A9D4-3C52BBD1F110`.
4. Write `01 01 00 01 01 01` **with response** to command characteristic
   `6F2A0002-7C93-4A58-A9D4-3C52BBD1F110`.

The write requests protocol 1, sequence 1, the `too fast` pattern, medium
intensity, once. Expected notifications are:

```text
01 01 00 00 00 01 00  # accepted
01 01 00 01 00 01 00  # completed
```

Writing the same sequence again must not replay the motor and returns:

```text
01 01 00 02 02 01 00  # rejected / invalid command
```

## Pattern and intensity calibration

The firmware uses DRV2605L real-time playback rather than effect-library IDs,
so pattern meaning does not change across driver library revisions. Pulse
timings live in `src/voxa_patterns.cpp` and playback is a `millis()`-driven
state machine. The initial amplitudes are deliberately conservative values on
the DRV2605L's positive RTP scale:

| App level | RTP amplitude |
| --- | --- |
| Soft | 45 |
| Medium | 75 |
| Strong | 105 |

Calibrate on the exact production motor and enclosure:

1. Verify the motor datasheet says LRA and 3 V rated operation. Do not test an
   unknown motor at Strong.
2. Start on Soft and preview every pattern while the band is worn normally.
3. Increase through Medium and Strong, checking that each level is distinct,
   the motor does not chatter against the enclosure, and it does not heat up.
4. If adjustment is required, change only the three return values in
   `amplitudeForIntensity`, retain `soft < medium < strong <= 127`, and rerun the
   native test suite.
5. Run the BLE smoke test for all seven pattern IDs and repeat counts 1–3, then
   wear-test continuously for 15 minutes before the demo.

If the specific LRA requires rated-voltage, overdrive-clamp, resonance, or
auto-calibration register values beyond the Adafruit library's `useLRA()`
configuration, derive them from that motor's datasheet and the TI DRV2605L
design procedure. Do not copy register values from a different motor.

## Design boundaries

- BLE is the only phone-to-wearable transport.
- The firmware receives semantic pattern IDs; speech analysis stays on iPhone.
- Status has protocol and firmware versions but no fabricated battery value.
- The mailbox and playback state use fixed-size storage. No Arduino `String`
  allocations occur in the command or haptic loop.
- Rebooting clears sequence history. The phone must continue increasing its
  16-bit sequence counter across ordinary BLE reconnects and must not replay
  commands generated before a reconnect.
