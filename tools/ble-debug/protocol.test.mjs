import assert from "node:assert/strict";
import test from "node:test";

import {
  correlateCommandStatus,
  decodeStatus,
  encodeCommand,
  formatHex,
  sequenceAfter,
} from "./protocol.mjs";

test("encodes the normative medium too-fast smoke-test packet", () => {
  const packet = encodeCommand({ sequence: 1, pattern: 1, intensity: 1, repeatCount: 1 });
  assert.deepEqual(Array.from(packet), [1, 1, 0, 1, 1, 1]);
  assert.equal(formatHex(packet), "01 01 00 01 01 01");
});

test("decodes accepted and completed status packets", () => {
  assert.deepEqual(decodeStatus(Uint8Array.of(1, 42, 0, 0, 0, 1, 0)), {
    sequence: 42,
    state: 0,
    stateLabel: "Accepted",
    error: 0,
    errorLabel: "None",
    firmware: "1.0",
  });
  assert.equal(decodeStatus(Uint8Array.of(1, 42, 0, 1, 0, 1, 0)).stateLabel, "Completed");
});

test("rejects malformed status and command values", () => {
  assert.throws(() => decodeStatus(Uint8Array.of(1, 1)), /7-byte/);
  assert.throws(() => decodeStatus(Uint8Array.of(2, 1, 0, 0, 0, 1, 0)), /protocol 1/);
  assert.throws(() => encodeCommand({ sequence: 0, pattern: 1, intensity: 1, repeatCount: 1 }), /sequence/);
  assert.throws(() => encodeCommand({ sequence: 1, pattern: 1, intensity: 3, repeatCount: 1 }), /intensity/);
  assert.throws(() => encodeCommand({ sequence: 1, pattern: 1, intensity: 1, repeatCount: 4 }), /repeat count/);
});

test("advances and wraps nonzero command sequences", () => {
  assert.equal(sequenceAfter(41), 42);
  assert.equal(sequenceAfter(65_535), 1);
});

test("requires a matching accepted status before completion can pass", () => {
  const pending = { sequence: 42, accepted: false };
  assert.deepEqual(correlateCommandStatus(pending, { sequence: 41, state: 1 }), {
    pending,
    event: "unrelated",
  });
  assert.equal(correlateCommandStatus(pending, { sequence: 42, state: 1 }).event, "completedWithoutAccepted");

  const accepted = correlateCommandStatus(pending, { sequence: 42, state: 0 });
  assert.deepEqual(accepted, {
    pending: { sequence: 42, accepted: true },
    event: "accepted",
  });
  assert.deepEqual(correlateCommandStatus(accepted.pending, { sequence: 42, state: 1 }), {
    pending: null,
    event: "completed",
  });
});

test("does not let terminal packets overwrite a completed command", () => {
  assert.deepEqual(correlateCommandStatus(null, { sequence: 42, state: 1 }), {
    pending: null,
    event: "unsolicited",
  });
  assert.deepEqual(correlateCommandStatus({ sequence: 42, accepted: true }, { sequence: 42, state: 2 }), {
    pending: null,
    event: "rejected",
  });
});
