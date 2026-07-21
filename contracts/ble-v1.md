# Voxa Cue BLE Protocol v1

The phone is the BLE central. Production Nano 33 IoT and supported Nano ESP32
firmware advertise as `Voxa Cue`. Centrals discover compatible devices by the
service UUID, never by the display name. All multi-byte integers are
little-endian.

## Security boundary

Protocol v1 is an unauthenticated control protocol for a closed, supervised
prototype. It does not require BLE pairing or bonding, link encryption, or
application-layer authentication. UUID discovery establishes compatibility,
and the monotonic sequence rejects stale or duplicate commands; neither proves
the identity of the phone or band. A nearby central that knows the UUIDs can
connect and write commands while the peripheral is available.

A public protocol revision must add authenticated device enrollment and
identity, replay-resistant authenticated commands, and connection, rate, and
actuator-duty limits. Implementations must not present protocol v1 as a private
or secure transport.

## GATT

| Role | UUID | Properties |
| --- | --- | --- |
| Cue service | `6F2A0001-7C93-4A58-A9D4-3C52BBD1F110` | Primary service |
| Command | `6F2A0002-7C93-4A58-A9D4-3C52BBD1F110` | Write with response |
| Status | `6F2A0003-7C93-4A58-A9D4-3C52BBD1F110` | Notify, read |
| Session light | `6F2A0004-7C93-4A58-A9D4-3C52BBD1F110` | Write with response; optional on firmware 1.1 and earlier |

## Command packet

Exactly six bytes:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | `uint8` | Protocol version; must equal `1` |
| 1-2 | `uint16` | Monotonic sequence number |
| 3 | `uint8` | Pattern ID |
| 4 | `uint8` | Intensity: `0` soft, `1` medium, `2` strong |
| 5 | `uint8` | Repeat count, `1...3` |

Pattern IDs describe physical pulse signatures, not coaching meaning. The app maps
each enabled cue to one of these signatures:

| ID | Signature |
| --- | --- |
| `1` | Two short pulses |
| `2` | One long pulse |
| `3` | Three quick pulses |
| `4` | Long-short-long |
| `5` | One firm pulse |
| `6` | Two firm pulses |
| `7` | Three firm pulses |
| `8` | One symmetric ramp up/down calm wave |
| `9` | One 1.2-second deadline hold |

IDs `1...7` retain their v1.0 waveforms. Firmware `1.1` adds IDs `8` and `9`
without changing the packet layout or protocol version.

## Session-light packet

Firmware `1.2` adds an optional, latest-value-wins session-light
characteristic without changing the haptic command or status packets.
Firmware `1.3` adds the opt-in overtime-buzzer mode to the same packet. It
accepts exactly three bytes:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | `uint8` | Protocol version; must equal `1` |
| 1 | `uint8` | Mode: `0` off, `1` active, `2` paused, `3` overtime, `4` overtime plus one-shot buzzer |
| 2 | `uint8` | Presentation time progress; must be in `0...100` |

The app writes active `0` when recording begins, sends updated progress plus a
heartbeat during the session, freezes the percentage in paused mode, sends
overtime after the target is exceeded, and sends off when the session ends or
fails. When the presenter explicitly enables the emergency buzzer for that
session, the app changes mode `3` to mode `4` at exactly 30 seconds overtime.
Firmware maps active and paused progress continuously from green at 0%,
through yellow at 50% and orange at 75%, to red at 100%. Overtime flashes red
for 500 ms on and 500 ms off.

The transition into mode `4` drives the D9 active-buzzer signal HIGH for
exactly 2,000 ms. Firmware latches delivery for the current session, so
heartbeat writes in mode `4` never restart the tone. Mode `0`, a disconnect,
or a stale heartbeat immediately silences the buzzer. Disconnect and timeout
preserve the per-session delivery latch, while mode `0` or the start of a new
active session resets it. The buzzer is independent of DRV2605L readiness.
Apps connected to firmware earlier than `1.3` must downgrade mode `4` to
ordinary overtime mode `3`.

Session-light writes are idempotent and have no status notification. The GATT
write response confirms transport only. Values above `100` and all other
malformed packets are ignored rather than clamped. The LED
turns off when the central disconnects or no valid heartbeat arrives for five
seconds. Apps must treat the characteristic as optional so firmware 1.1 and
earlier retain full haptic compatibility.

## Status packet

Exactly seven bytes:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | `uint8` | Protocol version |
| 1-2 | `uint16` | Sequence number |
| 3 | `uint8` | State: `0` accepted, `1` completed, `2` rejected |
| 4 | `uint8` | Error: `0` none, `1` invalid version, `2` invalid command, `3` driver fault |
| 5 | `uint8` | Firmware major |
| 6 | `uint8` | Firmware minor |

The peripheral sends `accepted` before playback and `completed` afterward. It
rejects duplicate completed sequence numbers without replaying the motor. A
driver fault rejects the command; while idle, firmware retries driver detection
once per second, and the app may send a fresh command with a new sequence after
readiness recovers. The app never replays commands generated before a reconnect.
