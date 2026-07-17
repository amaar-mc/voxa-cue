// @ts-check

export const DEFAULT_MOTION_CONFIG = Object.freeze({
  windowMilliseconds: 4_000,
  minimumSamples: 30,
  tooLittleUpperScore: 22,
  rightAmountUpperScore: 62,
  accelerationReferenceG: 0.35,
  gyroReferenceDegreesPerSecond: 160,
  activeAccelerationG: 0.08,
  activeGyroDegreesPerSecond: 35,
  activeFractionReference: 0.55,
});

/**
 * @typedef {{ receivedAtMilliseconds: number, acceleration: { x: number, y: number, z: number }, gyro: { x: number, y: number, z: number } }} TimedMotionSample
 * @typedef {{ windowMilliseconds: number, minimumSamples: number, tooLittleUpperScore: number, rightAmountUpperScore: number, accelerationReferenceG: number, gyroReferenceDegreesPerSecond: number, activeAccelerationG: number, activeGyroDegreesPerSecond: number, activeFractionReference: number }} MotionConfig
 */

/**
 * Produces a deterministic wrist-motion score from a rolling window.
 * Acceleration magnitude is orientation-independent, and subtracting 1 g
 * removes the stationary gravity vector. Gyroscope energy captures hand turns.
 *
 * @param {TimedMotionSample[]} samples
 * @param {MotionConfig} config
 * @returns {{ state: "calibrating" | "too-little" | "right-amount" | "too-much", label: string, score: number, accelerationRmsG: number, gyroRmsDegreesPerSecond: number, activeFraction: number, sampleCount: number }}
 */
export function classifyMotion(samples, config) {
  validateConfig(config);
  const latestTimestamp = samples.at(-1)?.receivedAtMilliseconds ?? 0;
  const windowStart = latestTimestamp - config.windowMilliseconds;
  const windowSamples = samples.filter(
    (sample) => sample.receivedAtMilliseconds >= windowStart,
  );

  if (windowSamples.length < config.minimumSamples) {
    return {
      state: "calibrating",
      label: "Gathering motion",
      score: 0,
      accelerationRmsG: 0,
      gyroRmsDegreesPerSecond: 0,
      activeFraction: 0,
      sampleCount: windowSamples.length,
    };
  }

  let accelerationSquaredTotal = 0;
  let gyroSquaredTotal = 0;
  let activeCount = 0;
  for (const sample of windowSamples) {
    const accelerationMagnitude = magnitude(sample.acceleration);
    const dynamicAcceleration = Math.abs(accelerationMagnitude - 1);
    const gyroMagnitude = magnitude(sample.gyro);
    accelerationSquaredTotal += dynamicAcceleration ** 2;
    gyroSquaredTotal += gyroMagnitude ** 2;
    if (
      dynamicAcceleration >= config.activeAccelerationG ||
      gyroMagnitude >= config.activeGyroDegreesPerSecond
    ) {
      activeCount += 1;
    }
  }

  const accelerationRmsG = Math.sqrt(
    accelerationSquaredTotal / windowSamples.length,
  );
  const gyroRmsDegreesPerSecond = Math.sqrt(
    gyroSquaredTotal / windowSamples.length,
  );
  const activeFraction = activeCount / windowSamples.length;
  const accelerationComponent = clamp01(
    accelerationRmsG / config.accelerationReferenceG,
  );
  const gyroComponent = clamp01(
    gyroRmsDegreesPerSecond / config.gyroReferenceDegreesPerSecond,
  );
  const activityComponent = clamp01(
    activeFraction / config.activeFractionReference,
  );
  const score = Math.round(
    100 *
      (0.4 * accelerationComponent +
        0.4 * gyroComponent +
        0.2 * activityComponent),
  );

  if (score < config.tooLittleUpperScore) {
    return result("too-little", "Move a little more", score, accelerationRmsG, gyroRmsDegreesPerSecond, activeFraction, windowSamples.length);
  }
  if (score <= config.rightAmountUpperScore) {
    return result("right-amount", "Movement is balanced", score, accelerationRmsG, gyroRmsDegreesPerSecond, activeFraction, windowSamples.length);
  }
  return result("too-much", "Settle your hands", score, accelerationRmsG, gyroRmsDegreesPerSecond, activeFraction, windowSamples.length);
}

/** @param {{ x: number, y: number, z: number }} vector */
function magnitude(vector) {
  return Math.hypot(vector.x, vector.y, vector.z);
}

/** @param {number} value */
function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

/**
 * @param {"too-little" | "right-amount" | "too-much"} state
 * @param {string} label
 * @param {number} score
 * @param {number} accelerationRmsG
 * @param {number} gyroRmsDegreesPerSecond
 * @param {number} activeFraction
 * @param {number} sampleCount
 */
function result(state, label, score, accelerationRmsG, gyroRmsDegreesPerSecond, activeFraction, sampleCount) {
  return { state, label, score, accelerationRmsG, gyroRmsDegreesPerSecond, activeFraction, sampleCount };
}

/** @param {MotionConfig} config */
function validateConfig(config) {
  if (
    config.windowMilliseconds <= 0 ||
    config.minimumSamples <= 0 ||
    config.tooLittleUpperScore < 0 ||
    config.rightAmountUpperScore <= config.tooLittleUpperScore ||
    config.rightAmountUpperScore > 100 ||
    config.accelerationReferenceG <= 0 ||
    config.gyroReferenceDegreesPerSecond <= 0 ||
    config.activeAccelerationG <= 0 ||
    config.activeGyroDegreesPerSecond <= 0 ||
    config.activeFractionReference <= 0
  ) {
    throw new Error("Motion classifier configuration is invalid.");
  }
}
