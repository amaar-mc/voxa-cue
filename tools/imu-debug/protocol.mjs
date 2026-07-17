// @ts-check

export const SERVICE_UUID = "7a3e1001-7c7b-4e25-9a5a-8d7c9f1a0001";
export const SAMPLE_UUID = "7a3e1002-7c7b-4e25-9a5a-8d7c9f1a0001";
export const INFO_UUID = "7a3e1003-7c7b-4e25-9a5a-8d7c9f1a0001";
export const PROTOCOL_VERSION = 1;

const SENSOR_NAMES = new Map([
  [0, "No sensor"],
  [1, "MPU-6050 family"],
  [2, "LSM6 family"],
  [255, "Unsupported I2C device"],
]);

const SENSOR_STATES = new Map([
  [0, "Ready"],
  [1, "Not found"],
  [2, "Unsupported"],
  [3, "Read fault"],
]);

/**
 * @param {DataView | Uint8Array} input
 * @returns {DataView}
 */
function asDataView(input) {
  return input instanceof DataView
    ? input
    : new DataView(input.buffer, input.byteOffset, input.byteLength);
}

/**
 * @param {DataView | Uint8Array} input
 * @returns {{ healthy: boolean, sequence: number, timestampMilliseconds: number, acceleration: { x: number, y: number, z: number }, gyro: { x: number, y: number, z: number } }}
 */
export function decodeSample(input) {
  const view = asDataView(input);
  if (view.byteLength !== 20) {
    throw new Error(`Expected a 20-byte IMU sample, received ${view.byteLength}.`);
  }
  if (view.getUint8(0) !== PROTOCOL_VERSION) {
    throw new Error(`Expected protocol ${PROTOCOL_VERSION}, received ${view.getUint8(0)}.`);
  }
  return {
    healthy: view.getUint8(1) === 1,
    sequence: view.getUint16(2, true),
    timestampMilliseconds: view.getUint32(4, true),
    acceleration: {
      x: view.getInt16(8, true) / 1000,
      y: view.getInt16(10, true) / 1000,
      z: view.getInt16(12, true) / 1000,
    },
    gyro: {
      x: view.getInt16(14, true) / 10,
      y: view.getInt16(16, true) / 10,
      z: view.getInt16(18, true) / 10,
    },
  };
}

/**
 * @param {DataView | Uint8Array} input
 * @returns {{ sensorKind: number, sensorName: string, address: number, addressHex: string, state: number, stateName: string, sampleRateHertz: number, firmware: string }}
 */
export function decodeInfo(input) {
  const view = asDataView(input);
  if (view.byteLength !== 8) {
    throw new Error(`Expected an 8-byte sensor-info packet, received ${view.byteLength}.`);
  }
  if (view.getUint8(0) !== PROTOCOL_VERSION) {
    throw new Error(`Expected protocol ${PROTOCOL_VERSION}, received ${view.getUint8(0)}.`);
  }

  const sensorKind = view.getUint8(1);
  const address = view.getUint8(2);
  const state = view.getUint8(3);
  return {
    sensorKind,
    sensorName: SENSOR_NAMES.get(sensorKind) ?? `Unknown sensor type ${sensorKind}`,
    address,
    addressHex: address === 0 ? "—" : `0x${address.toString(16).padStart(2, "0").toUpperCase()}`,
    state,
    stateName: SENSOR_STATES.get(state) ?? `Unknown state ${state}`,
    sampleRateHertz: view.getUint16(4, true),
    firmware: `${view.getUint8(6)}.${view.getUint8(7)}`,
  };
}
