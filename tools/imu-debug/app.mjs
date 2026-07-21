// @ts-check

import {
  DEFAULT_MOTION_CONFIG,
  classifyMotion,
} from "./motion-classifier.mjs";
import {
  INFO_UUID,
  SAMPLE_UUID,
  SERVICE_UUID,
  decodeInfo,
  decodeSample,
  requireHealthySample,
} from "./protocol.mjs";

const elements = {
  compatibility: requiredElement("compatibility"),
  connectionPill: requiredElement("connection-pill"),
  connectionState: requiredElement("connection-state"),
  connectButton: requiredButton("connect-button"),
  disconnectButton: requiredButton("disconnect-button"),
  deviceName: requiredElement("device-name"),
  deviceDetail: requiredElement("device-detail"),
  sensorState: requiredElement("sensor-state"),
  sensorName: requiredElement("sensor-name"),
  sensorAddress: requiredElement("sensor-address"),
  firmware: requiredElement("firmware"),
  sampleRate: requiredElement("sample-rate"),
  scoreCard: requiredElement("score-card"),
  motionLabel: requiredElement("motion-label"),
  motionGuidance: requiredElement("motion-guidance"),
  motionScore: requiredElement("motion-score"),
  scoreProgress: requiredSVGCircle("score-progress"),
  accelX: requiredElement("accel-x"),
  accelY: requiredElement("accel-y"),
  accelZ: requiredElement("accel-z"),
  gyroX: requiredElement("gyro-x"),
  gyroY: requiredElement("gyro-y"),
  gyroZ: requiredElement("gyro-z"),
  accelRms: requiredElement("accel-rms"),
  gyroRms: requiredElement("gyro-rms"),
  activeFraction: requiredElement("active-fraction"),
  lowThreshold: requiredInput("low-threshold"),
  highThreshold: requiredInput("high-threshold"),
  thresholdCopy: requiredElement("threshold-copy"),
  exportButton: requiredButton("export-button"),
  accelChart: requiredCanvas("accel-chart"),
  gyroChart: requiredCanvas("gyro-chart"),
};

/** @type {BluetoothDevice | null} */
let device = null;
/** @type {BluetoothRemoteGATTCharacteristic | null} */
let sampleCharacteristic = null;
/** @type {BluetoothRemoteGATTCharacteristic | null} */
let infoCharacteristic = null;
/** @type {Array<ReturnType<typeof decodeSample> & { receivedAtMilliseconds: number }>} */
let samples = [];
/** @type {number | null} */
let chartFrame = null;

elements.connectButton.addEventListener("click", connect);
elements.disconnectButton.addEventListener("click", disconnect);
elements.exportButton.addEventListener("click", exportCsv);
elements.lowThreshold.addEventListener("change", thresholdsChanged);
elements.highThreshold.addEventListener("change", thresholdsChanged);
window.addEventListener("resize", scheduleCharts);

showBrowserSupport();
drawCharts();

async function connect() {
  if (!("bluetooth" in navigator)) {
    showNotice("Open this page in desktop Google Chrome. Safari and iPhone browsers do not expose Web Bluetooth.");
    return;
  }

  setConnection("Choose Voxa IMU Lab", "working");
  try {
    device = await navigator.bluetooth.requestDevice({
      filters: [{ services: [SERVICE_UUID] }],
    });
    device.addEventListener("gattserverdisconnected", handleDisconnected);
    elements.deviceName.textContent = device.name ?? "Voxa IMU Lab";
    if (device.gatt === undefined) {
      throw new Error("The selected device has no BLE GATT server.");
    }

    setConnection("Connecting", "working");
    const server = await device.gatt.connect();
    const service = await server.getPrimaryService(SERVICE_UUID);
    sampleCharacteristic = await service.getCharacteristic(SAMPLE_UUID);
    infoCharacteristic = await service.getCharacteristic(INFO_UUID);

    infoCharacteristic.addEventListener("characteristicvaluechanged", receiveInfoEvent);
    sampleCharacteristic.addEventListener("characteristicvaluechanged", receiveSampleEvent);
    await infoCharacteristic.startNotifications();
    await sampleCharacteristic.startNotifications();
    receiveInfo(await infoCharacteristic.readValue());

    setConnection("Streaming", "ready");
    elements.connectButton.disabled = true;
    elements.disconnectButton.disabled = false;
    elements.deviceDetail.textContent = "Live notifications are arriving from the Nano over BLE.";
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setConnection("Connection failed", "error");
    showNotice(message.includes("User cancelled") ? "No device selected." : message);
  }
}

function disconnect() {
  device?.gatt?.disconnect();
  handleDisconnected();
}

function handleDisconnected() {
  sampleCharacteristic = null;
  infoCharacteristic = null;
  elements.connectButton.disabled = false;
  elements.disconnectButton.disabled = true;
  setConnection("Not connected", "idle");
  elements.deviceDetail.textContent = "The BLE stream ended. Reconnect after the Nano is powered.";
}

/** @param {Event} event */
function receiveInfoEvent(event) {
  const characteristic = /** @type {BluetoothRemoteGATTCharacteristic} */ (event.target);
  if (characteristic.value !== undefined) receiveInfo(characteristic.value);
}

/** @param {DataView} value */
function receiveInfo(value) {
  try {
    const info = decodeInfo(value);
    elements.sensorName.textContent = info.sensorName;
    elements.sensorAddress.textContent = info.addressHex;
    elements.firmware.textContent = info.firmware;
    elements.sampleRate.textContent = `${info.sampleRateHertz} Hz target`;
    elements.sensorState.textContent = info.stateName;
    elements.sensorState.className = `mini-badge ${info.state === 0 ? "ready" : "error"}`;
    if (info.state === 1) {
      elements.deviceDetail.textContent = "No I2C sensor answered. Check 3V3, GND, SDA/A4, and SCL/A5.";
    } else if (info.state === 2) {
      elements.deviceDetail.textContent = `A device answered at ${info.addressHex}, but its chip is not supported yet. Read the serial scan before adding an adapter.`;
    } else if (info.state === 3) {
      elements.deviceDetail.textContent = "The sensor was found but a register read failed. Check wiring and power stability.";
    }
  } catch (error) {
    showNotice(error instanceof Error ? error.message : String(error));
  }
}

/** @param {Event} event */
function receiveSampleEvent(event) {
  const characteristic = /** @type {BluetoothRemoteGATTCharacteristic} */ (event.target);
  if (characteristic.value === undefined) return;
  try {
    const decoded = requireHealthySample(decodeSample(characteristic.value));
    const receivedAtMilliseconds = performance.now();
    samples.push({ ...decoded, receivedAtMilliseconds });
    const historyStart = receivedAtMilliseconds - 15_000;
    samples = samples.filter((sample) => sample.receivedAtMilliseconds >= historyStart);
    renderSample(samples.at(-1));
    renderClassification();
    renderSampleRate();
    elements.exportButton.disabled = false;
    scheduleCharts();
  } catch (error) {
    showNotice(error instanceof Error ? error.message : String(error));
  }
}

/** @param {(ReturnType<typeof decodeSample> & { receivedAtMilliseconds: number }) | undefined} sample */
function renderSample(sample) {
  if (sample === undefined) return;
  elements.accelX.textContent = sample.acceleration.x.toFixed(3);
  elements.accelY.textContent = sample.acceleration.y.toFixed(3);
  elements.accelZ.textContent = sample.acceleration.z.toFixed(3);
  elements.gyroX.textContent = sample.gyro.x.toFixed(1);
  elements.gyroY.textContent = sample.gyro.y.toFixed(1);
  elements.gyroZ.textContent = sample.gyro.z.toFixed(1);
}

function renderClassification() {
  const result = classifyMotion(samples, currentMotionConfig());
  elements.scoreCard.dataset.state = result.state;
  elements.motionLabel.textContent = result.label;
  elements.motionScore.textContent = result.state === "calibrating" ? "—" : String(result.score);
  elements.scoreProgress.style.strokeDashoffset = String(314.16 * (1 - result.score / 100));
  elements.accelRms.textContent = result.state === "calibrating" ? "—" : `${result.accelerationRmsG.toFixed(3)} g`;
  elements.gyroRms.textContent = result.state === "calibrating" ? "—" : `${result.gyroRmsDegreesPerSecond.toFixed(1)} °/s`;
  elements.activeFraction.textContent = result.state === "calibrating" ? "—" : `${Math.round(result.activeFraction * 100)}%`;
  elements.motionGuidance.textContent = guidanceForState(result.state, result.sampleCount);
}

function renderSampleRate() {
  if (samples.length < 2) return;
  const newest = samples.at(-1);
  const cutoff = (newest?.receivedAtMilliseconds ?? 0) - 2_000;
  const recent = samples.filter((sample) => sample.receivedAtMilliseconds >= cutoff);
  if (recent.length < 2) return;
  const duration = (recent.at(-1).receivedAtMilliseconds - recent[0].receivedAtMilliseconds) / 1000;
  if (duration > 0) elements.sampleRate.textContent = `${((recent.length - 1) / duration).toFixed(1)} Hz live`;
}

function thresholdsChanged() {
  const config = currentMotionConfig();
  elements.thresholdCopy.textContent = `Balanced range: ${config.tooLittleUpperScore}–${config.rightAmountUpperScore}`;
  renderClassification();
}

/** @returns {typeof DEFAULT_MOTION_CONFIG} */
function currentMotionConfig() {
  const low = Number.parseInt(elements.lowThreshold.value, 10);
  const high = Number.parseInt(elements.highThreshold.value, 10);
  const tooLittleUpperScore = Number.isInteger(low) ? low : DEFAULT_MOTION_CONFIG.tooLittleUpperScore;
  const rightAmountUpperScore = Number.isInteger(high) && high > tooLittleUpperScore
    ? high
    : DEFAULT_MOTION_CONFIG.rightAmountUpperScore;
  return Object.freeze({
    ...DEFAULT_MOTION_CONFIG,
    tooLittleUpperScore,
    rightAmountUpperScore,
  });
}

/** @param {ReturnType<typeof classifyMotion>["state"]} state @param {number} sampleCount */
function guidanceForState(state, sampleCount) {
  if (state === "calibrating") return `Gathering a stable window · ${sampleCount} samples`;
  if (state === "too-little") return "Use one intentional gesture to underline your next idea.";
  if (state === "right-amount") return "Your hands are active without competing with your message.";
  return "Pause at a neutral resting position before the next point.";
}

function scheduleCharts() {
  if (chartFrame !== null) return;
  chartFrame = requestAnimationFrame(() => {
    chartFrame = null;
    drawCharts();
  });
}

function drawCharts() {
  drawChart(elements.accelChart, samples, "acceleration", 2);
  drawChart(elements.gyroChart, samples, "gyro", 300);
}

/**
 * @param {HTMLCanvasElement} canvas
 * @param {typeof samples} history
 * @param {"acceleration" | "gyro"} field
 * @param {number} absoluteScale
 */
function drawChart(canvas, history, field, absoluteScale) {
  const ratio = window.devicePixelRatio || 1;
  const width = Math.max(1, canvas.clientWidth);
  const height = Math.max(1, canvas.clientHeight);
  canvas.width = Math.round(width * ratio);
  canvas.height = Math.round(height * ratio);
  const context = canvas.getContext("2d");
  if (context === null) return;
  context.scale(ratio, ratio);
  context.clearRect(0, 0, width, height);

  context.strokeStyle = "rgba(17,43,43,.08)";
  context.lineWidth = 1;
  for (let row = 1; row < 4; row += 1) {
    const y = (height * row) / 4;
    context.beginPath();
    context.moveTo(0, y);
    context.lineTo(width, y);
    context.stroke();
  }

  const now = history.at(-1)?.receivedAtMilliseconds ?? performance.now();
  const start = now - 10_000;
  const visible = history.filter((sample) => sample.receivedAtMilliseconds >= start);
  const colors = { x: "#d25c48", y: "#11877b", z: "#d09a31" };
  for (const axis of /** @type {const} */ (["x", "y", "z"])) {
    context.strokeStyle = colors[axis];
    context.lineWidth = 2;
    context.lineJoin = "round";
    context.beginPath();
    visible.forEach((sample, index) => {
      const x = ((sample.receivedAtMilliseconds - start) / 10_000) * width;
      const bounded = Math.max(-absoluteScale, Math.min(absoluteScale, sample[field][axis]));
      const y = height / 2 - (bounded / absoluteScale) * (height * 0.43);
      if (index === 0) context.moveTo(x, y);
      else context.lineTo(x, y);
    });
    context.stroke();
  }
}

function exportCsv() {
  if (samples.length === 0) return;
  const lines = ["device_ms,received_ms,accel_x_g,accel_y_g,accel_z_g,gyro_x_dps,gyro_y_dps,gyro_z_dps"];
  for (const sample of samples) {
    lines.push([
      sample.timestampMilliseconds,
      Math.round(sample.receivedAtMilliseconds),
      sample.acceleration.x,
      sample.acceleration.y,
      sample.acceleration.z,
      sample.gyro.x,
      sample.gyro.y,
      sample.gyro.z,
    ].join(","));
  }
  const link = document.createElement("a");
  link.href = URL.createObjectURL(new Blob([`${lines.join("\n")}\n`], { type: "text/csv" }));
  link.download = `voxa-imu-${new Date().toISOString().replaceAll(":", "-")}.csv`;
  link.click();
  URL.revokeObjectURL(link.href);
}

function showBrowserSupport() {
  if (!("bluetooth" in navigator)) {
    showNotice("Web Bluetooth is unavailable here. Run the launcher and use desktop Google Chrome.");
  }
}

/** @param {string} message */
function showNotice(message) {
  elements.compatibility.textContent = message;
  elements.compatibility.classList.add("visible");
}

/** @param {string} label @param {"idle" | "working" | "ready" | "error"} tone */
function setConnection(label, tone) {
  elements.connectionState.textContent = label;
  elements.connectionPill.dataset.tone = tone;
}

/** @param {string} id */
function requiredElement(id) {
  const element = document.getElementById(id);
  if (element === null) throw new Error(`Missing #${id}.`);
  return element;
}

/** @param {string} id */
function requiredButton(id) {
  const element = requiredElement(id);
  if (!(element instanceof HTMLButtonElement)) throw new Error(`#${id} is not a button.`);
  return element;
}

/** @param {string} id */
function requiredInput(id) {
  const element = requiredElement(id);
  if (!(element instanceof HTMLInputElement)) throw new Error(`#${id} is not an input.`);
  return element;
}

/** @param {string} id */
function requiredCanvas(id) {
  const element = requiredElement(id);
  if (!(element instanceof HTMLCanvasElement)) throw new Error(`#${id} is not a canvas.`);
  return element;
}

/** @param {string} id */
function requiredSVGCircle(id) {
  const element = requiredElement(id);
  if (!(element instanceof SVGCircleElement)) throw new Error(`#${id} is not a circle.`);
  return element;
}
