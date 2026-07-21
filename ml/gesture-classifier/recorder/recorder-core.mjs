// @ts-check

export const RECORDING_SCHEMA_VERSION = 1;
export const EXPECTED_SENSOR_KIND = 2;
export const EXPECTED_SENSOR_ADDRESS = 0x6a;
export const EXPECTED_SAMPLE_RATE_HERTZ = 50;
export const EXPECTED_FIRMWARE = "1.1";
export const MINIMUM_PROMPT_REMAINING_MILLISECONDS = 500;

export const CSV_COLUMNS = Object.freeze([
  "schema_version",
  "subject_id",
  "session_id",
  "trial_id",
  "trial_started_at_utc",
  "behavior",
  "subtype",
  "wrist",
  "orientation",
  "repetition",
  "prompt_event_ms",
  "device_ms",
  "sequence",
  "sample_index",
  "elapsed_ms",
  "host_elapsed_ms",
  "accel_x_g",
  "accel_y_g",
  "accel_z_g",
  "gyro_x_dps",
  "gyro_y_dps",
  "gyro_z_dps",
  "sensor_kind",
  "sensor_address",
  "firmware",
  "target_sample_rate_hz",
  "healthy",
]);

/**
 * @typedef {{ id: string, label: string }} Subtype
 * @typedef {{ id: string, label: string, instruction: string, subtypes: Subtype[] }} Behavior
 * @typedef {{ behavior: string, behaviorLabel: string, subtype: string, subtypeLabel: string, instruction: string, repetition: number }} PlanEntry
 * @typedef {{ healthy: boolean, sequence: number, timestampMilliseconds: number, acceleration: { x: number, y: number, z: number }, gyro: { x: number, y: number, z: number }, receivedAtMilliseconds: number }} RecorderSample
 * @typedef {{ sensorKind: number, sensorName: string, address: number, addressHex: string, state: number, firmware: string, sampleRateHertz: number }} SensorInfo
 * @typedef {SensorInfo & { stateName: string }} DecodedSensorInfo
 * @typedef {{ subjectId: string, sessionId: string, wrist: "left" | "right", orientation: "usb_toward_hand" | "usb_toward_elbow" | "custom_consistent" }} SessionMetadata
 * @typedef {{ entry: PlanEntry, trialId: string, startedAtUtc: string, promptEventMilliseconds: number, samples: RecorderSample[], quality: ReturnType<typeof assessTrial>, sensorInfo: Readonly<SensorInfo> }} SavedTrial
 */

/**
 * Validate and freeze the exact sensor contract used to collect schema-v1 data.
 * @param {DecodedSensorInfo} info
 * @returns {Readonly<SensorInfo>}
 */
export function createSensorSnapshot(info) {
  const compatible = info.sensorKind === EXPECTED_SENSOR_KIND
    && info.address === EXPECTED_SENSOR_ADDRESS
    && info.state === 0
    && info.sampleRateHertz === EXPECTED_SAMPLE_RATE_HERTZ
    && info.firmware === EXPECTED_FIRMWARE;
  if (!compatible) {
    throw new Error(
      "Gesture collection requires diagnostic firmware 1.1, the onboard LSM6 at 0x6A, and a healthy 50 Hz stream.",
    );
  }
  return Object.freeze({
    sensorKind: info.sensorKind,
    sensorName: info.sensorName,
    address: info.address,
    addressHex: info.addressHex,
    state: info.state,
    firmware: info.firmware,
    sampleRateHertz: info.sampleRateHertz,
  });
}

/**
 * A prompted label is valid only when the cue appeared with time left to act.
 * @param {string} behavior
 * @param {number} promptEventMilliseconds
 * @param {number} captureDurationMilliseconds
 * @returns {string[]}
 */
export function promptTimingErrors(
  behavior,
  promptEventMilliseconds,
  captureDurationMilliseconds,
) {
  if (!Number.isFinite(promptEventMilliseconds) || promptEventMilliseconds < 0) {
    return [`The ${behavior.replaceAll("_", " ")} prompt was not displayed. Retry this take.`];
  }
  if (
    !Number.isFinite(captureDurationMilliseconds)
    || promptEventMilliseconds > (
      captureDurationMilliseconds - MINIMUM_PROMPT_REMAINING_MILLISECONDS
    )
  ) {
    return [
      `The prompt must appear at least ${MINIMUM_PROMPT_REMAINING_MILLISECONDS} ms before capture ends. Retry this take.`,
    ];
  }
  return [];
}

/** @param {string} value @param {string} label */
export function validateIdentifier(value, label) {
  const normalized = value.trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$/.test(normalized)) {
    throw new Error(`${label} must use 1–40 letters, numbers, underscores, or hyphens.`);
  }
  return normalized;
}

/**
 * @param {Behavior[]} behaviors
 * @param {Set<string>} selectedSubtypeIds
 * @param {number} repetitions
 * @param {() => number} randomSource
 * @returns {PlanEntry[]}
 */
export function buildRandomizedPlan(behaviors, selectedSubtypeIds, repetitions, randomSource) {
  if (!Number.isInteger(repetitions) || repetitions < 1 || repetitions > 50) {
    throw new Error("Repetitions must be an integer from 1 through 50.");
  }
  const selectedByBehavior = behaviors.map((behavior) => ({
    behavior,
    subtypes: behavior.subtypes.filter((subtype) => selectedSubtypeIds.has(subtype.id)),
  })).filter(({ subtypes }) => subtypes.length > 0);
  if (selectedByBehavior.length !== behaviors.length) {
    const missingBehaviors = behaviors
      .filter((behavior) => !selectedByBehavior.some(({ behavior: selected }) => (
        selected.id === behavior.id
      )))
      .map((behavior) => behavior.label);
    throw new Error(`Select at least one subtype for: ${missingBehaviors.join(", ")}.`);
  }

  const largestSubtypeCount = Math.max(
    ...selectedByBehavior.map(({ subtypes }) => subtypes.length),
  );
  const trialsPerBehavior = largestSubtypeCount * repetitions;
  const plan = [];
  for (const { behavior, subtypes } of selectedByBehavior) {
    for (let trialIndex = 0; trialIndex < trialsPerBehavior; trialIndex += 1) {
      const subtype = subtypes[trialIndex % subtypes.length];
      const repetition = Math.floor(trialIndex / subtypes.length) + 1;
      plan.push({
        behavior: behavior.id,
        behaviorLabel: behavior.label,
        subtype: subtype.id,
        subtypeLabel: subtype.label,
        instruction: behavior.instruction,
        repetition,
      });
    }
  }
  for (let index = plan.length - 1; index > 0; index -= 1) {
    const candidate = Math.floor(randomSource() * (index + 1));
    if (candidate < 0 || candidate > index) throw new Error("Random source returned an invalid value.");
    [plan[index], plan[candidate]] = [plan[candidate], plan[index]];
  }
  return plan;
}

/**
 * @param {RecorderSample[]} samples
 * @param {number} targetSampleRateHertz
 * @param {number} trialDurationSeconds
 * @param {number} minimumCaptureFraction
 * @param {number} maximumPacketLossFraction
 */
export function assessTrial(
  samples,
  targetSampleRateHertz,
  trialDurationSeconds,
  minimumCaptureFraction,
  maximumPacketLossFraction,
) {
  const errors = [];
  if (samples.length < 2) {
    return Object.freeze({
      accepted: false,
      errors: ["Fewer than two samples arrived."],
      sampleCount: samples.length,
      measuredRateHertz: 0,
      packetLossFraction: 1,
      durationSeconds: 0,
    });
  }

  const durationMilliseconds = elapsedDeviceMilliseconds(
    samples[0].timestampMilliseconds,
    samples.at(-1)?.timestampMilliseconds ?? samples[0].timestampMilliseconds,
  );
  const durationSeconds = durationMilliseconds / 1_000;
  const measuredRateHertz = durationSeconds > 0 ? (samples.length - 1) / durationSeconds : 0;
  const expectedSamples = targetSampleRateHertz * trialDurationSeconds;
  if (samples.length < expectedSamples * minimumCaptureFraction) {
    errors.push(`Only ${samples.length} of about ${Math.round(expectedSamples)} expected samples arrived.`);
  }
  if (durationSeconds < trialDurationSeconds * minimumCaptureFraction) {
    errors.push(`Only ${durationSeconds.toFixed(2)} seconds were captured.`);
  }
  if (samples.some((sample) => !sample.healthy)) {
    errors.push("The sensor reported an unhealthy packet.");
  }

  let missingPackets = 0;
  let duplicatePackets = 0;
  for (let index = 1; index < samples.length; index += 1) {
    const step = (samples[index].sequence - samples[index - 1].sequence + 65_536) % 65_536;
    if (step === 0) duplicatePackets += 1;
    else if (step > 1) missingPackets += step - 1;
  }
  if (duplicatePackets > 0) {
    errors.push(`Duplicate BLE packet sequence detected ${duplicatePackets} time(s).`);
  }
  const packetLossFraction = missingPackets / (samples.length + missingPackets);
  if (packetLossFraction > maximumPacketLossFraction) {
    errors.push(`Packet loss was ${(packetLossFraction * 100).toFixed(1)}%.`);
  }

  return Object.freeze({
    accepted: errors.length === 0,
    errors,
    sampleCount: samples.length,
    measuredRateHertz,
    packetLossFraction,
    durationSeconds,
  });
}

/** @param {number} startMilliseconds @param {number} currentMilliseconds */
export function elapsedDeviceMilliseconds(startMilliseconds, currentMilliseconds) {
  return (currentMilliseconds - startMilliseconds + 2 ** 32) % 2 ** 32;
}

/**
 * @param {SavedTrial[]} trials
 * @param {SessionMetadata} metadata
 */
export function serializeDatasetCsv(trials, metadata) {
  if (trials.length === 0) throw new Error("Record at least one accepted trial before exporting.");
  assertUniformSensorSignatures(trials);
  const lines = [CSV_COLUMNS.join(",")];
  for (const trial of trials) {
    const sensorInfo = trial.sensorInfo;
    const firstSample = trial.samples[0];
    for (let sampleIndex = 0; sampleIndex < trial.samples.length; sampleIndex += 1) {
      const sample = trial.samples[sampleIndex];
      const row = {
        schema_version: RECORDING_SCHEMA_VERSION,
        subject_id: metadata.subjectId,
        session_id: metadata.sessionId,
        trial_id: trial.trialId,
        trial_started_at_utc: trial.startedAtUtc,
        behavior: trial.entry.behavior,
        subtype: trial.entry.subtype,
        wrist: metadata.wrist,
        orientation: metadata.orientation,
        repetition: trial.entry.repetition,
        prompt_event_ms: trial.promptEventMilliseconds,
        device_ms: sample.timestampMilliseconds,
        sequence: sample.sequence,
        sample_index: sampleIndex,
        elapsed_ms: elapsedDeviceMilliseconds(firstSample.timestampMilliseconds, sample.timestampMilliseconds),
        host_elapsed_ms: sample.receivedAtMilliseconds - firstSample.receivedAtMilliseconds,
        accel_x_g: sample.acceleration.x,
        accel_y_g: sample.acceleration.y,
        accel_z_g: sample.acceleration.z,
        gyro_x_dps: sample.gyro.x,
        gyro_y_dps: sample.gyro.y,
        gyro_z_dps: sample.gyro.z,
        sensor_kind: sensorInfo.sensorName,
        sensor_address: sensorInfo.addressHex,
        firmware: sensorInfo.firmware,
        target_sample_rate_hz: sensorInfo.sampleRateHertz,
        healthy: sample.healthy,
      };
      lines.push(CSV_COLUMNS.map((column) => csvValue(row[column])).join(","));
    }
  }
  return `${lines.join("\n")}\n`;
}

/**
 * @param {SavedTrial[]} trials
 * @param {SessionMetadata} metadata
 * @param {number} plannedTrialCount
 */
export function buildManifest(trials, metadata, plannedTrialCount) {
  const sensorInfo = assertUniformSensorSignatures(trials);
  const subtypeCounts = {};
  for (const trial of trials) {
    subtypeCounts[trial.entry.subtype] = (subtypeCounts[trial.entry.subtype] ?? 0) + 1;
  }
  return Object.freeze({
    schemaVersion: RECORDING_SCHEMA_VERSION,
    exportedAtUtc: new Date().toISOString(),
    subjectId: metadata.subjectId,
    sessionId: metadata.sessionId,
    wrist: metadata.wrist,
    orientation: metadata.orientation,
    sensor: sensorInfo,
    plannedTrialCount,
    acceptedTrialCount: trials.length,
    subtypeCounts,
    quality: {
      meanSampleRateHertz: mean(trials.map((trial) => trial.quality.measuredRateHertz)),
      meanPacketLossFraction: mean(trials.map((trial) => trial.quality.packetLossFraction)),
    },
    warning: "Motion labels describe prompted behavior. They do not prove semantic intent.",
  });
}

/**
 * @param {SavedTrial[]} trials
 * @returns {Readonly<SensorInfo>}
 */
function assertUniformSensorSignatures(trials) {
  if (trials.length === 0) {
    throw new Error("Record at least one accepted trial before exporting.");
  }
  const first = trials[0].sensorInfo;
  const expectedSignature = sensorSignature(first);
  if (trials.some((trial) => sensorSignature(trial.sensorInfo) !== expectedSignature)) {
    throw new Error("Accepted trials contain multiple sensor signatures. Export or clear the session before changing devices.");
  }
  return first;
}

/** @param {Readonly<SensorInfo>} info */
function sensorSignature(info) {
  return [
    info.sensorKind,
    info.address,
    info.state,
    info.firmware,
    info.sampleRateHertz,
  ].join(":");
}

/** @param {unknown} value */
function csvValue(value) {
  const stringValue = String(value);
  if (!/[",\n\r]/.test(stringValue)) return stringValue;
  return `"${stringValue.replaceAll('"', '""')}"`;
}

/** @param {number[]} values */
function mean(values) {
  if (values.length === 0) return 0;
  return values.reduce((total, value) => total + value, 0) / values.length;
}
