// @ts-check

import {
  INFO_UUID,
  SAMPLE_UUID,
  SERVICE_UUID,
  decodeInfo,
  decodeSample,
} from "../../../tools/imu-debug/protocol.mjs";
import {
  assessTrial,
  buildManifest,
  buildRandomizedPlan,
  createSensorSnapshot,
  promptTimingErrors,
  serializeDatasetCsv,
  validateIdentifier,
} from "./recorder-core.mjs";

/** @typedef {import("./recorder-core.mjs").Behavior} Behavior */
/** @typedef {import("./recorder-core.mjs").PlanEntry} PlanEntry */
/** @typedef {import("./recorder-core.mjs").RecorderSample} RecorderSample */
/** @typedef {import("./recorder-core.mjs").SavedTrial} SavedTrial */
/** @typedef {import("./recorder-core.mjs").SensorInfo} SensorInfo */
/** @typedef {import("./recorder-core.mjs").SessionMetadata} SessionMetadata */

/**
 * @typedef {EventTarget & {
 *   value: DataView | undefined,
 *   startNotifications: () => Promise<unknown>,
 *   readValue: () => Promise<DataView>,
 * }} BleCharacteristic
 */

/**
 * @typedef {EventTarget & {
 *   name?: string,
 *   gatt?: {
 *     connect: () => Promise<{
 *       getPrimaryService: (uuid: string) => Promise<{
 *         getCharacteristic: (uuid: string) => Promise<BleCharacteristic>,
 *       }>,
 *     }>,
 *     disconnect: () => void,
 *   },
 * }} BleDevice
 */

/**
 * @typedef {{
 *   schemaVersion: number,
 *   behaviors: Behavior[],
 * }} LabelsConfig
 */

/**
 * @typedef {{
 *   schemaVersion: number,
 *   countdownSeconds: number,
 *   trialDurationSeconds: number,
 *   motionPromptMilliseconds: number,
 *   motionPromptDisplayMilliseconds: number,
 *   repetitionsPerSubtype: number,
 *   minimumCaptureFraction: number,
 *   maximumPacketLossFraction: number,
 *   recommendedSessionsPerSubject: number,
 *   recommendedNaturalValidationMinutes: number,
 *   modelingSampleRateHertz: number,
 *   windowSeconds: number,
 *   hopSeconds: number,
 * }} CollectionConfig
 */

const elements = {
  notice: requiredElement("notice"),
  connectionPill: requiredElement("connection-pill"),
  connectionState: requiredElement("connection-state"),
  connectButton: requiredButton("connect-button"),
  disconnectButton: requiredButton("disconnect-button"),
  sensorName: requiredElement("sensor-name"),
  sensorAddress: requiredElement("sensor-address"),
  sampleRate: requiredElement("sample-rate"),
  sensorVerification: requiredElement("sensor-verification"),
  subjectId: requiredInput("subject-id"),
  sessionId: requiredInput("session-id"),
  wrist: requiredSelect("wrist"),
  orientation: requiredSelect("orientation"),
  repetitions: requiredInput("repetitions"),
  behaviorList: requiredElement("behavior-list"),
  createPlanButton: requiredButton("create-plan-button"),
  progressCopy: requiredElement("progress-copy"),
  progressBar: requiredElement("progress-bar"),
  emptyState: requiredElement("empty-state"),
  promptPanel: requiredElement("prompt-panel"),
  behaviorName: requiredElement("behavior-name"),
  subtypeName: requiredElement("subtype-name"),
  instruction: requiredElement("instruction"),
  repetitionCopy: requiredElement("repetition-copy"),
  streamCopy: requiredElement("stream-copy"),
  captureStage: requiredElement("capture-stage"),
  captureValue: requiredElement("capture-value"),
  captureLabel: requiredElement("capture-label"),
  recordButton: requiredButton("record-button"),
  qualityPanel: requiredElement("quality-panel"),
  qualityKicker: requiredElement("quality-kicker"),
  qualityTitle: requiredElement("quality-title"),
  qualityIcon: requiredElement("quality-icon"),
  qualitySamples: requiredElement("quality-samples"),
  qualityRate: requiredElement("quality-rate"),
  qualityLoss: requiredElement("quality-loss"),
  qualityDuration: requiredElement("quality-duration"),
  qualityErrors: requiredElement("quality-errors"),
  keepButton: requiredButton("keep-button"),
  retryButton: requiredButton("retry-button"),
  skipButton: requiredButton("skip-button"),
  completePanel: requiredElement("complete-panel"),
  completeCopy: requiredElement("complete-copy"),
  downloadManifestButton: requiredButton("download-manifest-button"),
  downloadCsvButton: requiredButton("download-csv-button"),
};

/** @type {LabelsConfig | null} */
let labelsConfig = null;
/** @type {CollectionConfig | null} */
let collectionConfig = null;
/** @type {BleDevice | null} */
let device = null;
/** @type {BleCharacteristic | null} */
let infoCharacteristic = null;
/** @type {BleCharacteristic | null} */
let sampleCharacteristic = null;
let sampleStreaming = false;
/** @type {SensorInfo | null} */
let sensorInfo = null;
let sensorVerified = false;
/** @type {RecorderSample[]} */
let liveSamples = [];
/** @type {RecorderSample[] | null} */
let captureSamples = null;
/** @type {PlanEntry[]} */
let plan = [];
/** @type {SavedTrial[]} */
let savedTrials = [];
/** @type {{ planIndex: number, entry: PlanEntry }[]} */
let skippedEntries = [];
/** @type {SessionMetadata | null} */
let sessionMetadata = null;
/** @type {SavedTrial | null} */
let candidateTrial = null;
let planIndex = 0;
let attemptNumber = 0;
let operationEpoch = 0;
/** @type {"idle" | "countdown" | "recording"} */
let capturePhase = "idle";
/** @type {number | null} */
let captureProgressTimer = null;

elements.connectButton.addEventListener("click", connect);
elements.disconnectButton.addEventListener("click", disconnect);
elements.createPlanButton.addEventListener("click", createPlan);
elements.recordButton.addEventListener("click", beginCapture);
elements.keepButton.addEventListener("click", keepCandidate);
elements.retryButton.addEventListener("click", retryCandidate);
elements.skipButton.addEventListener("click", skipEntry);
elements.downloadCsvButton.addEventListener("click", downloadCsv);
elements.downloadManifestButton.addEventListener("click", downloadManifest);
document.addEventListener("visibilitychange", handleVisibilityChange);

showBrowserSupport();
await loadConfigs();

async function loadConfigs() {
  try {
    const [loadedLabels, loadedCollection] = await Promise.all([
      fetchJson("../configs/labels-v1.json"),
      fetchJson("../configs/collection-v1.json"),
    ]);
    labelsConfig = /** @type {LabelsConfig} */ (loadedLabels);
    collectionConfig = /** @type {CollectionConfig} */ (loadedCollection);
    renderBehaviorOptions(labelsConfig.behaviors);
    elements.repetitions.value = String(collectionConfig.repetitionsPerSubtype);
    elements.createPlanButton.disabled = false;
  } catch (error) {
    showNotice(`Recorder configuration failed to load: ${errorMessage(error)}`, "error");
  }
}

async function connect() {
  if (!("bluetooth" in navigator)) {
    showNotice("Open this page in desktop Google Chrome. Safari and iPhone browsers do not expose Web Bluetooth.", "error");
    return;
  }

  operationEpoch += 1;
  device?.removeEventListener("gattserverdisconnected", handleDisconnected);
  detachCharacteristicListeners();
  sensorVerified = false;
  sensorInfo = null;
  sampleStreaming = false;
  liveSamples = [];
  setConnection("Choose Voxa IMU Lab", "working");
  try {
    const bluetooth = /** @type {{ requestDevice: (options: { filters: { services: string[] }[] }) => Promise<BleDevice> }} */ (
      /** @type {unknown} */ (navigator["bluetooth"])
    );
    device = await bluetooth.requestDevice({ filters: [{ services: [SERVICE_UUID] }] });
    device.addEventListener("gattserverdisconnected", handleDisconnected);
    if (device.gatt === undefined) throw new Error("The selected device has no BLE GATT server.");

    setConnection("Connecting", "working");
    const server = await device.gatt.connect();
    const service = await server.getPrimaryService(SERVICE_UUID);
    infoCharacteristic = await service.getCharacteristic(INFO_UUID);
    sampleCharacteristic = await service.getCharacteristic(SAMPLE_UUID);
    const decodedInfo = decodeInfo(await infoCharacteristic.readValue());
    infoCharacteristic.addEventListener("characteristicvaluechanged", receiveInfoEvent);
    await infoCharacteristic.startNotifications();

    if (!applyDecodedSensorInfo(decodedInfo)) {
      setConnection("Sensor check failed", "error");
      elements.connectButton.disabled = true;
      elements.disconnectButton.disabled = false;
      updateRecordAvailability();
      return;
    }

    sampleCharacteristic.addEventListener("characteristicvaluechanged", receiveSampleEvent);
    await sampleCharacteristic.startNotifications();
    sampleStreaming = true;
    setConnection("Onboard IMU ready", "ready");
    elements.connectButton.disabled = true;
    elements.disconnectButton.disabled = false;
    showNotice("Verified the Nano 33 IoT onboard LSM6 IMU at 0x6A. Samples remain in this tab.", "success");
    updateRecordAvailability();
  } catch (error) {
    device?.removeEventListener("gattserverdisconnected", handleDisconnected);
    device?.gatt?.disconnect();
    device = null;
    detachCharacteristicListeners();
    infoCharacteristic = null;
    sampleCharacteristic = null;
    sensorInfo = null;
    sensorVerified = false;
    sampleStreaming = false;
    setConnection("Connection failed", "error");
    elements.connectButton.disabled = false;
    elements.disconnectButton.disabled = true;
    showNotice(errorMessage(error).includes("User cancelled") ? "No device selected." : errorMessage(error), "error");
  }
}

function disconnect() {
  abortActiveCapture("Capture stopped because the Nano disconnected.");
  device?.removeEventListener("gattserverdisconnected", handleDisconnected);
  device?.gatt?.disconnect();
  handleDisconnected();
}

function handleDisconnected() {
  const captureWasActive = capturePhase !== "idle";
  operationEpoch += 1;
  device?.removeEventListener("gattserverdisconnected", handleDisconnected);
  device = null;
  if (captureProgressTimer !== null) {
    window.clearInterval(captureProgressTimer);
    captureProgressTimer = null;
  }
  captureSamples = null;
  capturePhase = "idle";
  liveSamples = [];
  detachCharacteristicListeners();
  infoCharacteristic = null;
  sampleCharacteristic = null;
  sampleStreaming = false;
  sensorInfo = null;
  sensorVerified = false;
  elements.connectButton.disabled = false;
  elements.disconnectButton.disabled = true;
  setConnection("Nano not connected", "idle");
  elements.sensorVerification.textContent = "Disconnected";
  elements.sensorVerification.dataset.state = "idle";
  elements.createPlanButton.disabled = labelsConfig === null || collectionConfig === null;
  if (candidateTrial !== null) renderQuality(candidateTrial);
  else if (plan.length > 0 && planIndex < plan.length) renderPrompt();
  if (captureWasActive) {
    showNotice("Take cancelled because the Nano disconnected. Reconnect and retry it.", "error");
  }
  updateRecordAvailability();
}

/** @param {Event} event */
function receiveInfoEvent(event) {
  const characteristic = /** @type {BleCharacteristic} */ (event.target);
  if (characteristic.value === undefined) return;
  try {
    const decodedInfo = decodeInfo(characteristic.value);
    if (applyDecodedSensorInfo(decodedInfo)) return;
    abortActiveCapture("Capture invalidated because the onboard IMU reported a fault or incompatible state.");
  } catch (error) {
    sensorVerified = false;
    sensorInfo = null;
    setConnection("Sensor update invalid", "error");
    abortActiveCapture("Capture invalidated by an unreadable sensor-status packet.");
    showNotice(`Invalid sensor-status packet: ${errorMessage(error)}`, "error");
    updateRecordAvailability();
  }
}

/** @param {ReturnType<typeof decodeInfo>} decodedInfo */
function applyDecodedSensorInfo(decodedInfo) {
  renderSensorInfo(decodedInfo);
  try {
    sensorInfo = createSensorSnapshot(decodedInfo);
  } catch (error) {
    sensorInfo = null;
    sensorVerified = false;
    setConnection("Sensor check failed", "error");
    showNotice(`${errorMessage(error)} ${sensorFailureMessage(decodedInfo)}`, "error");
    updateRecordAvailability();
    return false;
  }
  sensorVerified = true;
  setConnection("Onboard IMU ready", "ready");
  updateRecordAvailability();
  return true;
}

/** @param {Event} event */
function receiveSampleEvent(event) {
  if (!sensorVerified || !sampleStreaming) return;
  const characteristic = /** @type {BleCharacteristic} */ (event.target);
  if (characteristic.value === undefined) return;
  try {
    const sample = {
      ...decodeSample(characteristic.value),
      receivedAtMilliseconds: performance.now(),
    };
    liveSamples.push(sample);
    const cutoff = sample.receivedAtMilliseconds - 2_000;
    liveSamples = liveSamples.filter((candidate) => candidate.receivedAtMilliseconds >= cutoff);
    if (captureSamples !== null) captureSamples.push(sample);
    renderLiveRate();
  } catch (error) {
    showNotice(`Dropped an invalid BLE packet: ${errorMessage(error)}`, "error");
  }
}

function createPlan() {
  if (labelsConfig === null || collectionConfig === null) return;
  if (plan.length > 0 && (savedTrials.length > 0 || skippedEntries.length > 0)) {
    const confirmed = window.confirm("Rebuilding the plan clears every trial currently held in this tab. Continue?");
    if (!confirmed) return;
  }

  try {
    const metadata = readSessionMetadata();
    const repetitions = Number(elements.repetitions.value);
    const selectedSubtypes = new Set(
      Array.from(elements.behaviorList.querySelectorAll("input[type='checkbox']:checked"))
        .map((input) => /** @type {HTMLInputElement} */ (input).value),
    );
    const nextPlan = buildRandomizedPlan(labelsConfig.behaviors, selectedSubtypes, repetitions, Math.random);

    operationEpoch += 1;
    sessionMetadata = metadata;
    plan = nextPlan;
    savedTrials = [];
    skippedEntries = [];
    candidateTrial = null;
    planIndex = 0;
    attemptNumber = 0;
    elements.createPlanButton.textContent = "Rebuild randomized plan";
    updateExportAvailability();
    renderPrompt();
    showNotice(`${plan.length} prompted trials randomized. Keep the band orientation unchanged for the full session.`, "success");
    document.querySelector(".trial-card")?.scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (error) {
    showNotice(errorMessage(error), "error");
  }
}

async function beginCapture() {
  if (collectionConfig === null || sensorInfo === null || sessionMetadata === null) return;
  if (!sensorVerified || !sampleStreaming || planIndex >= plan.length || capturePhase !== "idle") return;

  const entry = plan[planIndex];
  const captureSensorInfo = sensorInfo;
  const epoch = ++operationEpoch;
  capturePhase = "countdown";
  elements.recordButton.disabled = true;
  elements.createPlanButton.disabled = true;
  candidateTrial = null;
  elements.captureStage.dataset.state = "countdown";

  for (let seconds = collectionConfig.countdownSeconds; seconds > 0; seconds -= 1) {
    if (epoch !== operationEpoch || !sensorVerified) return;
    elements.captureValue.textContent = String(seconds);
    elements.captureLabel.textContent = "Prepare the prompted movement.";
    await delay(1_000);
  }
  if (epoch !== operationEpoch || !sensorVerified) return;

  attemptNumber += 1;
  const startedAtUtc = new Date().toISOString();
  const trialId = `${sessionMetadata.subjectId}_${sessionMetadata.sessionId}_${String(attemptNumber).padStart(4, "0")}`;
  captureSamples = [];
  capturePhase = "recording";
  elements.captureStage.dataset.state = "recording";
  elements.captureValue.textContent = "Record";
  elements.captureLabel.textContent = "Speak naturally. Follow the movement cue when it appears.";

  const startedAtMilliseconds = performance.now();
  let promptEventMilliseconds = -1;
  captureProgressTimer = window.setInterval(() => {
    const elapsedMilliseconds = performance.now() - startedAtMilliseconds;
    const remaining = Math.max(
      0,
      collectionConfig.trialDurationSeconds - elapsedMilliseconds / 1_000,
    );
    const motionPromptVisible = elapsedMilliseconds >= collectionConfig.motionPromptMilliseconds
      && elapsedMilliseconds < (
        collectionConfig.motionPromptMilliseconds
        + collectionConfig.motionPromptDisplayMilliseconds
      );
    if (promptEventMilliseconds < 0
      && elapsedMilliseconds >= collectionConfig.motionPromptMilliseconds) {
      promptEventMilliseconds = Math.round(elapsedMilliseconds);
    }
    elements.captureValue.textContent = motionPromptVisible
      ? motionPromptLabel(entry.behavior)
      : remaining.toFixed(1);
  }, 80);
  await delay(collectionConfig.trialDurationSeconds * 1_000);
  const completedDurationMilliseconds = performance.now() - startedAtMilliseconds;
  if (captureProgressTimer !== null) {
    window.clearInterval(captureProgressTimer);
    captureProgressTimer = null;
  }
  if (epoch !== operationEpoch || captureSamples === null) return;

  const completedSamples = captureSamples;
  captureSamples = null;
  capturePhase = "idle";
  let quality = assessTrial(
    completedSamples,
    captureSensorInfo.sampleRateHertz,
    collectionConfig.trialDurationSeconds,
    collectionConfig.minimumCaptureFraction,
    collectionConfig.maximumPacketLossFraction,
  );
  const timingErrors = promptTimingErrors(
    entry.behavior,
    promptEventMilliseconds,
    completedDurationMilliseconds,
  );
  if (timingErrors.length > 0) {
    quality = Object.freeze({
      ...quality,
      accepted: false,
      errors: [...quality.errors, ...timingErrors],
    });
  }
  candidateTrial = {
    entry,
    trialId,
    startedAtUtc,
    promptEventMilliseconds,
    samples: completedSamples,
    quality,
    sensorInfo: captureSensorInfo,
  };
  elements.createPlanButton.disabled = false;
  renderQuality(candidateTrial);
}

function keepCandidate() {
  if (candidateTrial === null || !candidateTrial.quality.accepted) return;
  savedTrials.push(candidateTrial);
  candidateTrial = null;
  planIndex += 1;
  updateExportAvailability();
  advancePlan();
}

function retryCandidate() {
  candidateTrial = null;
  renderPrompt();
}

function skipEntry() {
  if (planIndex >= plan.length) return;
  skippedEntries.push({ planIndex, entry: plan[planIndex] });
  candidateTrial = null;
  planIndex += 1;
  advancePlan();
}

function advancePlan() {
  renderProgress();
  if (planIndex >= plan.length) {
    renderComplete();
  } else {
    renderPrompt();
  }
}

function handleVisibilityChange() {
  if (document.visibilityState === "visible" || capturePhase === "idle") return;
  abortActiveCapture("Take cancelled because the recorder left the foreground. Keep this tab visible during countdown and capture.");
}

/** @param {string} message */
function abortActiveCapture(message) {
  if (capturePhase === "idle") return;
  operationEpoch += 1;
  if (captureProgressTimer !== null) {
    window.clearInterval(captureProgressTimer);
    captureProgressTimer = null;
  }
  captureSamples = null;
  capturePhase = "idle";
  candidateTrial = null;
  elements.createPlanButton.disabled = labelsConfig === null || collectionConfig === null;
  if (plan.length > 0 && planIndex < plan.length) renderPrompt();
  showNotice(message, "error");
}

function detachCharacteristicListeners() {
  infoCharacteristic?.removeEventListener("characteristicvaluechanged", receiveInfoEvent);
  sampleCharacteristic?.removeEventListener("characteristicvaluechanged", receiveSampleEvent);
}

/** @param {string} behavior */
function motionPromptLabel(behavior) {
  if (behavior === "rest") return "Stay still";
  if (behavior === "intentional_gesture") return "Gesture now";
  if (behavior === "fidget") return "Fidget now";
  throw new Error(`Unsupported behavior prompt: ${behavior}`);
}

function renderPrompt() {
  if (plan.length === 0 || planIndex >= plan.length) return;
  const entry = plan[planIndex];
  elements.emptyState.hidden = true;
  elements.completePanel.hidden = true;
  elements.qualityPanel.hidden = true;
  elements.promptPanel.hidden = false;
  elements.behaviorName.textContent = entry.behaviorLabel;
  elements.subtypeName.textContent = entry.subtypeLabel;
  elements.instruction.textContent = entry.instruction;
  elements.repetitionCopy.textContent = `Take ${entry.repetition} for this movement`;
  elements.captureStage.dataset.state = "ready";
  elements.captureValue.textContent = "Ready";
  elements.captureLabel.textContent = "Hold your wrist in a natural speaking position.";
  renderProgress();
  updateRecordAvailability();
}

/** @param {SavedTrial} trial */
function renderQuality(trial) {
  const quality = trial.quality;
  elements.promptPanel.hidden = true;
  elements.qualityPanel.hidden = false;
  elements.qualityPanel.dataset.state = quality.accepted ? "passed" : "failed";
  elements.qualityKicker.textContent = quality.accepted ? "Take passed" : "Retake needed";
  elements.qualityTitle.textContent = quality.accepted ? "Clean capture" : "Quality gate failed";
  elements.qualityIcon.textContent = quality.accepted ? "✓" : "!";
  elements.qualitySamples.textContent = String(quality.sampleCount);
  elements.qualityRate.textContent = `${quality.measuredRateHertz.toFixed(1)} Hz`;
  elements.qualityLoss.textContent = `${(quality.packetLossFraction * 100).toFixed(1)}%`;
  elements.qualityDuration.textContent = `${quality.durationSeconds.toFixed(2)} s`;
  elements.qualityErrors.replaceChildren(...quality.errors.map((message) => {
    const item = document.createElement("li");
    item.textContent = message;
    return item;
  }));
  elements.keepButton.disabled = !quality.accepted;
}

function renderComplete() {
  elements.emptyState.hidden = true;
  elements.promptPanel.hidden = true;
  elements.qualityPanel.hidden = true;
  elements.completePanel.hidden = false;
  elements.completeCopy.textContent = `${savedTrials.length} accepted, ${skippedEntries.length} skipped. Download both files before closing this tab.`;
  elements.progressCopy.textContent = `${plan.length} / ${plan.length}`;
  elements.progressBar.style.width = "100%";
}

function renderProgress() {
  if (plan.length === 0) {
    elements.progressCopy.textContent = "No plan";
    elements.progressBar.style.width = "0%";
    return;
  }
  elements.progressCopy.textContent = `${planIndex} / ${plan.length}`;
  elements.progressBar.style.width = `${(planIndex / plan.length) * 100}%`;
}

function renderLiveRate() {
  if (liveSamples.length < 2) return;
  const first = liveSamples[0];
  const last = liveSamples.at(-1);
  if (last === undefined) return;
  const durationSeconds = (last.receivedAtMilliseconds - first.receivedAtMilliseconds) / 1_000;
  if (durationSeconds <= 0) return;
  const rate = (liveSamples.length - 1) / durationSeconds;
  elements.streamCopy.textContent = `${rate.toFixed(1)} Hz live`;
  elements.sampleRate.textContent = `${rate.toFixed(1)} Hz live`;
}

/** @param {ReturnType<typeof decodeInfo>} info */
function renderSensorInfo(info) {
  elements.sensorName.textContent = info.sensorName;
  elements.sensorAddress.textContent = info.addressHex;
  elements.sampleRate.textContent = `${info.sampleRateHertz} Hz target · firmware ${info.firmware}`;
  let verified = false;
  try {
    createSensorSnapshot(info);
    verified = true;
  } catch {
    verified = false;
  }
  elements.sensorVerification.textContent = verified ? "Onboard IMU verified" : info.stateName;
  elements.sensorVerification.dataset.state = verified ? "ready" : "error";
}

/** @param {ReturnType<typeof decodeInfo>} info */
function sensorFailureMessage(info) {
  if (info.state !== 0) return `The IMU reported “${info.stateName}”. Reflash the diagnostic firmware and power-cycle the Nano.`;
  if (info.sensorKind !== 2 || info.address !== 0x6a) {
    return `Expected the Nano 33 IoT onboard LSM6 IMU at 0x6A, but found ${info.sensorName} at ${info.addressHex}.`;
  }
  if (info.firmware !== "1.1") return `Firmware ${info.firmware} is incompatible. Flash diagnostic firmware 1.1.`;
  return `The diagnostic firmware reported ${info.sampleRateHertz} Hz instead of 50 Hz.`;
}

function updateRecordAvailability() {
  elements.recordButton.disabled = !sensorVerified
    || !sampleStreaming
    || plan.length === 0
    || planIndex >= plan.length
    || capturePhase !== "idle";
  if (plan.length > 0 && planIndex < plan.length) {
    elements.streamCopy.textContent = sensorVerified ? "IMU stream ready" : "Connect the Nano to record";
  }
}

function updateExportAvailability() {
  const available = savedTrials.length > 0;
  elements.downloadCsvButton.disabled = !available;
  elements.downloadManifestButton.disabled = !available;
}

function downloadCsv() {
  if (sessionMetadata === null) return;
  try {
    const csv = serializeDatasetCsv(savedTrials, sessionMetadata);
    downloadBlob(csv, "text/csv;charset=utf-8", `${fileStem(sessionMetadata)}.csv`);
  } catch (error) {
    showNotice(errorMessage(error), "error");
  }
}

function downloadManifest() {
  if (sessionMetadata === null || collectionConfig === null || labelsConfig === null) return;
  try {
    const baseManifest = buildManifest(savedTrials, sessionMetadata, plan.length);
    const manifest = {
      ...baseManifest,
      collectionProtocol: collectionConfig,
      labelSchemaVersion: labelsConfig.schemaVersion,
      plannedTrialOrder: plan.map((entry, index) => ({ order: index + 1, ...entry })),
      skippedPrompts: skippedEntries.map(({ planIndex: skippedIndex, entry }) => ({ order: skippedIndex + 1, ...entry })),
      storageBoundary: "Browser memory only until explicit local download. No network upload.",
    };
    downloadBlob(`${JSON.stringify(manifest, null, 2)}\n`, "application/json", `${fileStem(sessionMetadata)}-manifest.json`);
  } catch (error) {
    showNotice(errorMessage(error), "error");
  }
}

/** @returns {SessionMetadata} */
function readSessionMetadata() {
  const subjectId = validateIdentifier(elements.subjectId.value, "Participant ID");
  const sessionId = validateIdentifier(elements.sessionId.value, "Session ID");
  const wrist = elements.wrist.value;
  const orientation = elements.orientation.value;
  if (wrist !== "left" && wrist !== "right") throw new Error("Choose a recorded wrist.");
  if (orientation !== "usb_toward_hand" && orientation !== "usb_toward_elbow" && orientation !== "custom_consistent") {
    throw new Error("Choose a band orientation.");
  }
  return { subjectId, sessionId, wrist, orientation };
}

/** @param {Behavior[]} behaviors */
function renderBehaviorOptions(behaviors) {
  const groups = behaviors.map((behavior) => {
    const section = document.createElement("section");
    section.className = "behavior-group";

    const header = document.createElement("div");
    header.className = "behavior-header";
    const label = document.createElement("strong");
    label.textContent = behavior.label;
    const instruction = document.createElement("span");
    instruction.textContent = behavior.instruction;
    header.append(label, instruction);

    const choices = document.createElement("div");
    choices.className = "subtypes";
    for (const subtype of behavior.subtypes) {
      const option = document.createElement("label");
      option.className = "subtype-option";
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.value = subtype.id;
      checkbox.checked = true;
      const copy = document.createElement("span");
      copy.textContent = subtype.label;
      option.append(checkbox, copy);
      choices.append(option);
    }
    section.append(header, choices);
    return section;
  });
  elements.behaviorList.replaceChildren(...groups);
}

function showBrowserSupport() {
  if (!("bluetooth" in navigator)) {
    showNotice("Web Bluetooth is unavailable here. Run serve.sh and use desktop Google Chrome.", "error");
  }
}

/** @param {string} message @param {"success" | "error"} tone */
function showNotice(message, tone) {
  elements.notice.textContent = message;
  elements.notice.dataset.tone = tone;
  elements.notice.classList.add("visible");
}

/** @param {string} label @param {"idle" | "working" | "ready" | "error"} tone */
function setConnection(label, tone) {
  elements.connectionState.textContent = label;
  elements.connectionPill.dataset.tone = tone;
}

/** @param {string} content @param {string} type @param {string} filename */
function downloadBlob(content, type, filename) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 0);
}

/** @param {SessionMetadata} metadata */
function fileStem(metadata) {
  return `voxa-gestures-${metadata.subjectId}-${metadata.sessionId}`;
}

/** @param {number} milliseconds */
function delay(milliseconds) {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

/** @param {string} path */
async function fetchJson(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`${path} returned HTTP ${response.status}.`);
  return response.json();
}

/** @param {unknown} error */
function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
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
function requiredSelect(id) {
  const element = requiredElement(id);
  if (!(element instanceof HTMLSelectElement)) throw new Error(`#${id} is not a select.`);
  return element;
}
