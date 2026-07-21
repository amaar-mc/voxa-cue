import test from "node:test";
import assert from "node:assert/strict";

import { decodeInfo, decodeSample, requireHealthySample } from "./protocol.mjs";

test("decodes signed IMU axes and units", () => {
  const bytes = new Uint8Array(20);
  const view = new DataView(bytes.buffer);
  view.setUint8(0, 1);
  view.setUint8(1, 1);
  view.setUint16(2, 513, true);
  view.setUint32(4, 12_345, true);
  view.setInt16(8, 1_250, true);
  view.setInt16(10, -500, true);
  view.setInt16(12, 1_000, true);
  view.setInt16(14, 123, true);
  view.setInt16(16, -456, true);
  view.setInt16(18, 0, true);

  assert.deepEqual(decodeSample(bytes), {
    healthy: true,
    sequence: 513,
    timestampMilliseconds: 12_345,
    acceleration: { x: 1.25, y: -0.5, z: 1 },
    gyro: { x: 12.3, y: -45.6, z: 0 },
  });
});

test("decodes sensor identity and I2C address", () => {
  const bytes = Uint8Array.of(1, 1, 0x68, 0, 50, 0, 1, 1);
  assert.deepEqual(decodeInfo(bytes), {
    sensorKind: 1,
    sensorName: "MPU-6050 family",
    address: 0x68,
    addressHex: "0x68",
    state: 0,
    stateName: "Ready",
    sampleRateHertz: 50,
    firmware: "1.1",
  });
});

test("rejects truncated packets", () => {
  assert.throws(() => decodeSample(new Uint8Array(19)), /20-byte/);
  assert.throws(() => decodeInfo(new Uint8Array(7)), /8-byte/);
});

test("rejects unhealthy samples before dashboard classification", () => {
  const bytes = new Uint8Array(20);
  const view = new DataView(bytes.buffer);
  view.setUint8(0, 1);
  view.setUint8(1, 0);
  view.setUint16(2, 514, true);

  assert.throws(
    () => requireHealthySample(decodeSample(bytes)),
    /Sensor read fault.*ignored/,
  );
});
