import test from "node:test";
import assert from "node:assert/strict";

import {
  classifyMotion,
  DEFAULT_MOTION_CONFIG,
} from "./motion-classifier.mjs";

function samples(count, acceleration, gyro) {
  return Array.from({ length: count }, (_, index) => ({
    receivedAtMilliseconds: index * 40,
    acceleration,
    gyro,
  }));
}

test("classifies a still wrist as too little movement", () => {
  const result = classifyMotion(
    samples(100, { x: 0, y: 0, z: 1 }, { x: 1, y: 1, z: 1 }),
    DEFAULT_MOTION_CONFIG,
  );
  assert.equal(result.state, "too-little");
  assert.ok(result.score < 22);
});

test("classifies moderate gestures as the right amount", () => {
  const result = classifyMotion(
    samples(100, { x: 0.35, y: 0, z: 1.05 }, { x: 55, y: 35, z: 20 }),
    DEFAULT_MOTION_CONFIG,
  );
  assert.equal(result.state, "right-amount");
  assert.ok(result.score >= 22 && result.score <= 62);
});

test("classifies vigorous gestures as too much movement", () => {
  const result = classifyMotion(
    samples(100, { x: 1, y: 0.8, z: 1.3 }, { x: 220, y: 140, z: 90 }),
    DEFAULT_MOTION_CONFIG,
  );
  assert.equal(result.state, "too-much");
  assert.ok(result.score > 62);
});

test("waits for enough samples before judging", () => {
  const result = classifyMotion(
    samples(10, { x: 1, y: 0, z: 1 }, { x: 200, y: 0, z: 0 }),
    DEFAULT_MOTION_CONFIG,
  );
  assert.equal(result.state, "calibrating");
});
