# Voxa Cue BLE Protocol v1

The phone is the BLE central. The Nano ESP32 advertises as `Voxa Cue` and is the peripheral. All multi-byte integers are little-endian.

## GATT

| Role | UUID | Properties |
| --- | --- | --- |
| Cue service | `6F2A0001-7C93-4A58-A9D4-3C52BBD1F110` | Primary service |
| Command | `6F2A0002-7C93-4A58-A9D4-3C52BBD1F110` | Write with response |
| Status | `6F2A0003-7C93-4A58-A9D4-3C52BBD1F110` | Notify, read |

## Command packet

Exactly six bytes:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | `uint8` | Protocol version; must equal `1` |
| 1-2 | `uint16` | Monotonic sequence number |
| 3 | `uint8` | Pattern ID |
| 4 | `uint8` | Intensity: `0` soft, `1` medium, `2` strong |
| 5 | `uint8` | Repeat count, `1...3` |

Pattern IDs: `1` too fast, `2` too slow, `3` filler burst, `4` deck behind, `5` time 75%, `6` time 90%, `7` time 100%.

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

The peripheral sends `accepted` before playback and `completed` afterward. It rejects duplicate completed sequence numbers without replaying the motor. The app never replays commands generated before a reconnect.

