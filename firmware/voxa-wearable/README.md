# Voxa Cue wearable firmware

Firmware v1.0 turns either an Arduino Nano 33 IoT or Nano ESP32 into the same
BLE v1 peripheral. Both accept versioned, semantic haptic commands from the
Voxa Cue iPhone app and drive a 3 V LRA through a DRV2605L in real-time
playback mode. The main loop never blocks for the length of a vibration.

The wire contract is defined in [`../../contracts/ble-v1.md`](../../contracts/ble-v1.md).
The implementation rejects malformed packets, unsupported protocol versions,
busy commands, stale or duplicate sequence numbers, and commands received when
the motor driver is unavailable. Every valid command reports `accepted`, then
`completed`; a driver failure reports `rejected / driver fault`.

## Hardware

- Arduino Nano 33 IoT or Arduino Nano ESP32
- DRV2605L breakout at I2C address `0x5A`
- 3 V LRA coin vibration motor
- Data-capable USB cable matching the board (Micro-USB for Nano 33 IoT;
  USB-C for Nano ESP32)

Wire with all power disconnected:

| Either Nano | DRV2605L breakout | Purpose |
| --- | --- | --- |
| `3V3` | `VIN` | Driver power for the bench prototype |
| `GND` | `GND` | Shared ground |
| `SDA` / `A4` | `SDA` | I2C data |
| `SCL` / `A5` | `SCL` | I2C clock |
| — | `OUT+` / `OUT-` | LRA motor leads; polarity is not significant |

Do not connect the motor directly to a Nano GPIO or directly across 3V3/GND.
It must connect only to the DRV2605L output. Confirm that the particular
breakout accepts 3.3 V on `VIN`; boards with a different input requirement need
the power arrangement specified by their manufacturer. A wearable battery
requires a protected cell, charging circuit, and appropriate regulation—do not
connect a bare LiPo as a substitute for USB power.

The SAMD21 firmware uses the Nano 33 IoT board's default `Wire` bus, so do not
move I2C to alternate GPIOs. The board is a 3.3 V device; never expose its I/O
pins to 5 V. Arduino's official
[Nano 33 IoT pinout](https://docs.arduino.cc/resources/pinouts/ABX00027-full-pinout.pdf)
is the source of truth when checking board labels.

## Nano 33 IoT connectivity-firmware prerequisite

This project pins ArduinoBLE 2.1.0. ArduinoBLE 2.x requires the Nano 33 IoT's
NINA-W102 connectivity firmware to be **3.0.0 or newer**, as specified in the
[official ArduinoBLE compatibility table](https://github.com/arduino-libraries/ArduinoBLE#firmware-compatibility).
Update the NINA module before debugging the app connection; flashing this
PlatformIO project updates the SAMD21 application but does not update the NINA
module.

Use Arduino IDE's Firmware Updater or Arduino Cloud to update the module. The
official Arduino support guides explain how to
[check the installed WiFiNINA firmware](https://support.arduino.cc/hc/en-us/articles/9398559561244-Check-the-WiFiNINA-firmware-version)
and
[update the connectivity module](https://support.arduino.cc/hc/en-us/articles/10501616961564-Update-connectivity-module-firmware-with-Arduino-Cloud).

## Build, test, and flash

PlatformIO is invoked through `uvx`, so no global installation is required.
`--with pip` is required because PlatformIO installs Python helpers for the
ESP32 flashing toolchain on its first run:

```sh
cd firmware/voxa-wearable
uvx --with pip platformio test -e native
uvx --with pip platformio run -e nano_33_iot
uvx --with pip platformio run -e nano_33_iot --target upload
uvx --with pip platformio run -e nano_esp32
uvx --with pip platformio run -e nano_esp32 --target upload
uvx --with pip platformio device monitor --baud 115200
```

For the current Nano 33 IoT prototype, use the `nano_33_iot` environment. The
Nano ESP32 environment remains available and exposes the identical device
name, service UUIDs, command packet, status packet, and vibration programs.

If PlatformIO cannot find the upload port, list ports with
`uvx --with pip platformio device list`, then pass the result explicitly with
`--upload-port /dev/cu.usbmodem...`.

If the Nano 33 IoT does not enter its bootloader for upload, double-press its
reset button, wait for the pulsing bootloader LED, list ports again, and upload
to the newly appeared `/dev/cu.usbmodem...` port.

On startup the serial monitor prints either `Voxa Cue firmware 1.1 ready` or a
DRV2605L detection failure. A missing driver does not crash BLE; commands are
rejected with the protocol's `driver fault` error.

### Temporary D2 PWM diagnostic

The `nano_33_iot_direct_pwm_test` environment reproduces the prototype test
sketch's PWM behavior on Nano pin `D2` while retaining the current Voxa Cue BLE
v1 service, command packets, status packets, and vibration patterns. It does
not initialize, detect, or test a DRV2605L.

Use this environment only when `D2` is connected to a high-impedance,
3.3 V-compatible logic input on a separately powered motor-driver module and
the module shares ground with the Nano. Never connect a bare vibration motor
directly to `D2`; the motor can exceed the GPIO current limit and its inductive
kick can damage the Nano.

With USB, battery, and every other power source disconnected, verify that
topology before flashing. Then run:

```sh
uvx --with pip platformio run -e nano_33_iot_direct_pwm_test --target upload
uvx --with pip platformio device monitor --baud 115200
```

The monitor must print `Voxa Cue D2 PWM diagnostic ready`, and the board
advertises as `Voxa D2` to distinguish it from production firmware. The Chrome
BLE tester and iPhone Device Lab can then send their normal commands. A
`completed` status means the Nano executed the PWM timing; confirm the physical
vibration yourself because this diagnostic path has no motor-feedback signal.

Restore the production DRV2605L firmware after the test:

```sh
uvx --with pip platformio run -e nano_33_iot --target upload
```

## BLE smoke test

The repository includes a desktop Chrome tester that explains each connection
stage, subscribes to status packets, and sends a selectable haptic command:

```sh
pnpm ble:debug
```

Keep that terminal open, close the Voxa Cue iPhone app, and click **Find Voxa
Cue** in the Chrome page. The page runs only on localhost; Safari and iPhone
browsers do not support this Web Bluetooth workflow. It does not replace
flashing: the Nano must already be running this firmware and advertising.

Alternatively, use a BLE inspector such as LightBlue:

1. Connect to `Voxa Cue`.
2. Open service `6F2A0001-7C93-4A58-A9D4-3C52BBD1F110`.
3. Subscribe to status characteristic
   `6F2A0003-7C93-4A58-A9D4-3C52BBD1F110`.
4. Write `01 01 00 01 01 01` **with response** to command characteristic
   `6F2A0002-7C93-4A58-A9D4-3C52BBD1F110`.

The write requests protocol 1, sequence 1, the two-short pattern, medium
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
5. Run the BLE smoke test for all nine pattern IDs and repeat counts 1–3, then
   wear-test continuously for 15 minutes before the demo.

If the specific LRA requires rated-voltage, overdrive-clamp, resonance, or
auto-calibration register values beyond the Adafruit library's `useLRA()`
configuration, derive them from that motor's datasheet and the TI DRV2605L
design procedure. Do not copy register values from a different motor.

## Design boundaries

- BLE is the only phone-to-wearable transport.
- Nano 33 IoT uses ArduinoBLE; Nano ESP32 uses NimBLE-Arduino. Both transports
  implement the same BLE v1 contract.
- The firmware receives physical pattern IDs; cue meaning and speech analysis stay on iPhone.
- Status has protocol and firmware versions but no fabricated battery value.
- The mailbox and playback state use fixed-size storage. No Arduino `String`
  allocations occur in the command or haptic loop.
- Rebooting clears sequence history. The phone must continue increasing its
  16-bit sequence counter across ordinary BLE reconnects and must not replay
  commands generated before a reconnect.
