# Voxa Cue wearable firmware

Firmware v1.3 turns either an Arduino Nano 33 IoT or Nano ESP32 into the same
BLE v1 peripheral. Both accept versioned, semantic haptic commands from the
Voxa Cue iPhone app and drive a 3 V LRA through a DRV2605L in real-time
playback mode. They also drive a session-progress RGB LED and an optional
one-shot overtime buzzer. The main loop never blocks for the length of a
vibration or tone.

The wire contract is defined in [`../../contracts/ble-v1.md`](../../contracts/ble-v1.md).
The implementation rejects malformed packets, unsupported protocol versions,
busy commands, stale or duplicate sequence numbers, and commands received when
the motor driver is unavailable. Every valid command reports `accepted`, then
`completed`; a driver failure reports `rejected / driver fault`.

## Hardware

- Arduino Nano 33 IoT or Arduino Nano ESP32
- DRV2605L breakout at I2C address `0x5A`
- 3 V LRA coin vibration motor
- Common-cathode RGB LED with one 220–330 Ω resistor per color leg
- 3.3 V-compatible active-buzzer module or transistor-switched active buzzer
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

Wire the session light separately:

| Nano | RGB LED | Purpose |
| --- | --- | --- |
| `D6` | Red through 220–330 Ω | Red channel |
| `D7` | Green through 220–330 Ω | Green channel |
| `D8` | Blue through 220–330 Ω | Blue channel; reserved and off in the current gradient |
| `GND` | Common cathode | Shared LED return |

Wire the optional overtime buzzer separately:

| Nano | Active-buzzer module | Purpose |
| --- | --- | --- |
| `D9` | Signal input | Active HIGH tone control |
| `3V3` | `VCC` | Module power when rated for 3.3 V |
| `GND` | `GND` | Shared ground |

Do not power a high-current raw buzzer from D9. D9 is only for a
3.3 V-compatible high-impedance signal input or a correctly sized transistor
driver. Firmware 1.3 holds D9 HIGH for exactly two seconds once, 30 seconds
after the target, only when the option was enabled in session setup.

The Nano 33 IoT is a 3.3 V device with a low GPIO current limit. Never omit
the three current-limiting resistors and never connect an LED common pin to 5 V.
The requested `D7` and `D8` pins do not expose stock hardware PWM on Nano 33
IoT, so firmware uses nonblocking 32-step software PWM. For a common-anode LED,
connect the common leg to `3V3` and add `-DVOXA_RGB_COMMON_ANODE` to the selected
PlatformIO environment's `build_flags`; do not use that flag with a
common-cathode LED.

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

On startup the serial monitor prints either `Voxa Cue firmware 1.3 ready` or a
DRV2605L detection failure. A missing driver does not crash BLE; commands are
rejected with the protocol's `driver fault` error.

The production firmware has no direct-GPIO or MOSFET motor-output mode. Every
haptic command requires a detected DRV2605L on the default I2C bus and is
rejected with `driver fault` if address `0x5A` is unavailable.

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
01 01 00 00 00 01 03  # accepted
01 01 00 01 00 01 03  # completed
```

Writing the same sequence again must not replay the motor and returns:

```text
01 01 00 02 02 01 03  # rejected / invalid command
```

To test the RGB timing channel, write `01 01 32` with response to
`6F2A0004-7C93-4A58-A9D4-3C52BBD1F110`. This requests active mode at 50% and
should show yellow. Write `01 03 64` for flashing red overtime, then `01 00 00`
to turn the LED off. With an active-buzzer module wired safely to D9, write
`01 04 64` to start one two-second tone. Repeating that mode-4 packet must not
restart the tone until an off packet begins a new session.

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
- The firmware receives only session mode and a bounded timing percentage for the RGB light.
- Status has protocol and firmware versions but no fabricated battery value.
- The mailbox and playback state use fixed-size storage. No Arduino `String`
  allocations occur in the command or haptic loop.
- Rebooting clears sequence history. The phone must continue increasing its
  16-bit sequence counter across ordinary BLE reconnects and must not replay
  commands generated before a reconnect.
