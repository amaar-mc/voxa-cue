import assert from "node:assert/strict";
import test from "node:test";

import {
  assessTrial,
  buildManifest,
  buildRandomizedPlan,
  createSensorSnapshot,
  elapsedDeviceMilliseconds,
  promptTimingErrors,
  serializeDatasetCsv,
  validateIdentifier,
} from "./recorder-core.mjs";

const behaviors = [
  {
    id: "rest",
    label: "Rest",
    instruction: "Stay still",
    subtypes: [{ id: "still", label: "Still" }],
  },
  {
    id: "fidget",
    label: "Fidget",
    instruction: "Fidget",
    subtypes: [{ id: "wrist_twist", label: "Wrist twist" }],
  },
];

test("builds a balanced randomized plan", () => {
  const randomValues = [0.1, 0.8, 0.2, 0.6, 0.3];
  let randomIndex = 0;
  const plan = buildRandomizedPlan(
    behaviors,
    new Set(["still", "wrist_twist"]),
    3,
    () => randomValues[randomIndex++ % randomValues.length],
  );

  assert.equal(plan.length, 6);
  assert.equal(plan.filter((entry) => entry.subtype === "still").length, 3);
  assert.equal(plan.filter((entry) => entry.subtype === "wrist_twist").length, 3);
});

test("balances behaviors that have different subtype counts", () => {
  const unbalancedBehaviors = [
    behaviors[0],
    {
      ...behaviors[1],
      subtypes: [
        { id: "wrist_twist", label: "Wrist twist" },
        { id: "strap_touch", label: "Strap touch" },
      ],
    },
  ];
  const plan = buildRandomizedPlan(
    unbalancedBehaviors,
    new Set(["still", "wrist_twist", "strap_touch"]),
    2,
    () => 0.5,
  );

  assert.equal(plan.filter((entry) => entry.behavior === "rest").length, 4);
  assert.equal(plan.filter((entry) => entry.behavior === "fidget").length, 4);
  assert.equal(plan.filter((entry) => entry.subtype === "still").at(-1)?.repetition, 4);
});

test("requires every behavior in a collection plan", () => {
  assert.throws(
    () => buildRandomizedPlan(behaviors, new Set(["still"]), 2, () => 0.5),
    /at least one subtype for: Fidget/,
  );
});

test("rejects invalid participant identifiers", () => {
  assert.equal(validateIdentifier(" P001 ", "Subject ID"), "P001");
  assert.throws(() => validateIdentifier("Amaar Chughtai", "Subject ID"), /letters/);
});

test("accepts only the exact Nano 33 IoT diagnostic contract", () => {
  const compatible = decodedSensorInfo();
  const snapshot = createSensorSnapshot(compatible);

  assert.deepEqual(snapshot, {
    sensorKind: 2,
    sensorName: "LSM6 family",
    address: 0x6a,
    addressHex: "0x6A",
    state: 0,
    firmware: "1.1",
    sampleRateHertz: 50,
  });
  assert.equal(Object.isFrozen(snapshot), true);

  for (const incompatible of [
    { ...compatible, sensorKind: 1 },
    { ...compatible, address: 0x6b, addressHex: "0x6B" },
    { ...compatible, state: 3 },
    { ...compatible, firmware: "1.0" },
    { ...compatible, sampleRateHertz: 25 },
  ]) {
    assert.throws(() => createSensorSnapshot(incompatible), /requires diagnostic firmware 1\.1/);
  }
});

test("rejects missing and late prompts for every behavior", () => {
  assert.deepEqual(promptTimingErrors("rest", 1_500, 4_000), []);
  assert.deepEqual(promptTimingErrors("fidget", 1_500, 4_000), []);
  assert.deepEqual(promptTimingErrors("intentional_gesture", 1_500, 4_000), []);
  assert.match(
    promptTimingErrors("intentional_gesture", -1, 4_000)[0],
    /was not displayed/,
  );
  assert.match(
    promptTimingErrors("intentional_gesture", 3_600, 4_000)[0],
    /at least 500 ms/,
  );
});

test("assesses packet continuity including sequence rollover", () => {
  const samples = Array.from({ length: 200 }, (_, index) => sample(index, (65_500 + index) % 65_536));
  const quality = assessTrial(samples, 50, 4, 0.8, 0.05);

  assert.equal(quality.accepted, true);
  assert.equal(quality.packetLossFraction, 0);
  assert.ok(quality.measuredRateHertz > 49 && quality.measuredRateHertz < 51);
});

test("rejects high packet loss", () => {
  const samples = Array.from({ length: 100 }, (_, index) => sample(index * 2, index * 2));
  const quality = assessTrial(samples, 50, 4, 0.4, 0.05);

  assert.equal(quality.accepted, false);
  assert.ok(quality.errors.some((message) => message.includes("Packet loss")));
});

test("rejects duplicate BLE sequence numbers during capture", () => {
  const samples = Array.from({ length: 200 }, (_, index) => sample(index, index));
  samples[100].sequence = samples[99].sequence;
  const quality = assessTrial(samples, 50, 4, 0.8, 0.05);

  assert.equal(quality.accepted, false);
  assert.ok(quality.errors.some((message) => message.includes("Duplicate BLE packet")));
});

test("serializes labels and device-relative timing", () => {
  const first = sample(0, 10);
  first.timestampMilliseconds = 0xfffffff0;
  const second = sample(1, 11);
  second.timestampMilliseconds = 4;
  const quality = assessTrial([first, second], 50, 0.02, 0.5, 0.5);
  const csv = serializeDatasetCsv(
    [{
      entry: {
        behavior: "intentional_gesture",
        behaviorLabel: "Intentional gesture",
        subtype: "beat",
        subtypeLabel: "Beat",
        instruction: "Gesture",
        repetition: 1,
      },
      trialId: "P001_S01_0001",
      startedAtUtc: "2026-07-20T12:00:00.000Z",
      promptEventMilliseconds: 1_500,
      samples: [first, second],
      quality,
      sensorInfo: sensorSnapshot(),
    }],
    {
      subjectId: "P001",
      sessionId: "S01",
      wrist: "right",
      orientation: "usb_toward_elbow",
    },
  );

  assert.match(csv, /intentional_gesture,beat/);
  assert.match(csv, /,1,1500,/);
  assert.match(csv, /,20,20,/);
});

test("rejects mixed sensor signatures instead of rewriting trial provenance", () => {
  const samples = Array.from({ length: 200 }, (_, index) => sample(index, index));
  const quality = assessTrial(samples, 50, 4, 0.8, 0.05);
  const firstTrial = savedTrial("P001_S01_0001", samples, quality, sensorSnapshot());
  const incompatibleSnapshot = Object.freeze({
    ...sensorSnapshot(),
    firmware: "1.2",
  });
  const secondTrial = savedTrial("P001_S01_0002", samples, quality, incompatibleSnapshot);

  assert.throws(
    () => serializeDatasetCsv([firstTrial, secondTrial], sessionMetadata()),
    /multiple sensor signatures/,
  );
});

test("handles uint32 device timestamp rollover", () => {
  assert.equal(elapsedDeviceMilliseconds(0xfffffff0, 4), 20);
});

test("builds a quality manifest without raw samples", () => {
  const samples = Array.from({ length: 200 }, (_, index) => sample(index, index));
  const quality = assessTrial(samples, 50, 4, 0.8, 0.05);
  const metadata = sessionMetadata();
  const manifest = buildManifest([{
    entry: {
      behavior: "fidget",
      behaviorLabel: "Fidget",
      subtype: "wrist_twist",
      subtypeLabel: "Wrist twist",
      instruction: "Fidget",
      repetition: 1,
    },
    trialId: "P001_S01_0001",
    startedAtUtc: "2026-07-20T12:00:00.000Z",
    promptEventMilliseconds: 1_500,
    samples,
    quality,
    sensorInfo: sensorSnapshot(),
  }], metadata, 3);

  assert.equal(manifest.acceptedTrialCount, 1);
  assert.equal(manifest.plannedTrialCount, 3);
  assert.equal(manifest.subtypeCounts.wrist_twist, 1);
  assert.equal("samples" in manifest, false);
  assert.match(manifest.warning, /do not prove semantic intent/);
});

function decodedSensorInfo() {
  return {
    sensorKind: 2,
    sensorName: "LSM6 family",
    address: 0x6a,
    addressHex: "0x6A",
    state: 0,
    stateName: "Ready",
    firmware: "1.1",
    sampleRateHertz: 50,
  };
}

function sensorSnapshot() {
  return createSensorSnapshot(decodedSensorInfo());
}

function sessionMetadata() {
  return {
    subjectId: "P001",
    sessionId: "S01",
    wrist: "right",
    orientation: "usb_toward_elbow",
  };
}

function savedTrial(trialId, samples, quality, sensorInfo) {
  return {
    entry: {
      behavior: "fidget",
      behaviorLabel: "Fidget",
      subtype: "wrist_twist",
      subtypeLabel: "Wrist twist",
      instruction: "Fidget",
      repetition: 1,
    },
    trialId,
    startedAtUtc: "2026-07-20T12:00:00.000Z",
    promptEventMilliseconds: 1_500,
    samples,
    quality,
    sensorInfo,
  };
}

function sample(index, sequence) {
  return {
    healthy: true,
    sequence,
    timestampMilliseconds: index * 20,
    receivedAtMilliseconds: index * 20,
    acceleration: { x: 0, y: 0, z: 1 },
    gyro: { x: 0, y: 0, z: 0 },
  };
}
