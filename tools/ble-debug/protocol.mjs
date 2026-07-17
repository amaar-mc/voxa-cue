export const BLE_PROTOCOL_VERSION = 1;
export const SERVICE_UUID = "6f2a0001-7c93-4a58-a9d4-3c52bbd1f110";
export const COMMAND_UUID = "6f2a0002-7c93-4a58-a9d4-3c52bbd1f110";
export const STATUS_UUID = "6f2a0003-7c93-4a58-a9d4-3c52bbd1f110";

const STATUS_STATES = ["Accepted", "Completed", "Rejected"];
const STATUS_ERRORS = ["None", "Invalid protocol version", "Invalid command", "Haptic driver fault"];

/** @typedef {{ sequence: number, accepted: boolean }} PendingCommand */

/**
 * @param {{ sequence: number, pattern: number, intensity: number, repeatCount: number }} command
 * @returns {Uint8Array}
 */
export function encodeCommand(command) {
  assertIntegerInRange("sequence", command.sequence, 1, 65_535);
  assertIntegerInRange("pattern", command.pattern, 1, 9);
  assertIntegerInRange("intensity", command.intensity, 0, 2);
  assertIntegerInRange("repeat count", command.repeatCount, 1, 3);

  return Uint8Array.of(
    BLE_PROTOCOL_VERSION,
    command.sequence & 0xff,
    (command.sequence >> 8) & 0xff,
    command.pattern,
    command.intensity,
    command.repeatCount,
  );
}

/**
 * @param {Uint8Array} bytes
 * @returns {{ sequence: number, state: number, stateLabel: string, error: number, errorLabel: string, firmware: string }}
 */
export function decodeStatus(bytes) {
  if (bytes.byteLength !== 7) {
    throw new Error(`Expected a 7-byte status packet, received ${bytes.byteLength}.`);
  }
  if (bytes[0] !== BLE_PROTOCOL_VERSION) {
    throw new Error(`Expected BLE protocol 1, received ${bytes[0]}.`);
  }

  const stateLabel = STATUS_STATES[bytes[3]];
  const errorLabel = STATUS_ERRORS[bytes[4]];
  if (stateLabel === undefined || errorLabel === undefined) {
    throw new Error("The status packet contains an unknown state or error code.");
  }

  return {
    sequence: bytes[1] | (bytes[2] << 8),
    state: bytes[3],
    stateLabel,
    error: bytes[4],
    errorLabel,
    firmware: `${bytes[5]}.${bytes[6]}`,
  };
}

/**
 * @param {number} sequence
 * @returns {number}
 */
export function sequenceAfter(sequence) {
  assertIntegerInRange("sequence", sequence, 1, 65_535);
  return sequence === 65_535 ? 1 : sequence + 1;
}

/**
 * @param {PendingCommand | null} pending
 * @param {{ sequence: number, state: number }} status
 * @returns {{ pending: PendingCommand | null, event: "unsolicited" | "unrelated" | "accepted" | "completed" | "completedWithoutAccepted" | "rejected" }}
 */
export function correlateCommandStatus(pending, status) {
  if (pending === null) {
    return { pending: null, event: "unsolicited" };
  }
  if (pending.sequence !== status.sequence) {
    return { pending, event: "unrelated" };
  }
  if (status.state === 0) {
    return { pending: { sequence: pending.sequence, accepted: true }, event: "accepted" };
  }
  if (status.state === 1) {
    return pending.accepted
      ? { pending: null, event: "completed" }
      : { pending: null, event: "completedWithoutAccepted" };
  }
  return { pending: null, event: "rejected" };
}

/**
 * @param {Uint8Array} bytes
 * @returns {string}
 */
export function formatHex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0").toUpperCase()).join(" ");
}

/**
 * @param {string} label
 * @param {number} value
 * @param {number} minimum
 * @param {number} maximum
 */
function assertIntegerInRange(label, value, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${label} must be an integer from ${minimum} through ${maximum}.`);
  }
}
