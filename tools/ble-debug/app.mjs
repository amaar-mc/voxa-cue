import {
  COMMAND_UUID,
  SERVICE_UUID,
  STATUS_UUID,
  correlateCommandStatus,
  decodeStatus,
  encodeCommand,
  formatHex,
  sequenceAfter,
} from "./protocol.mjs";

const elements = {
  compatibility: requiredElement("compatibility"),
  connectionDot: requiredElement("connection-dot"),
  connectionState: requiredElement("connection-state"),
  connectionDetail: requiredElement("connection-detail"),
  findButton: requiredButton("find-button"),
  broadScanButton: requiredButton("broad-scan-button"),
  reconnectButton: requiredButton("reconnect-button"),
  disconnectButton: requiredButton("disconnect-button"),
  deviceName: requiredElement("device-name"),
  deviceID: requiredElement("device-id"),
  firmware: requiredElement("firmware"),
  pattern: requiredSelect("pattern"),
  intensity: requiredSelect("intensity"),
  repeatCount: requiredSelect("repeat-count"),
  sequence: requiredInput("sequence"),
  sendButton: requiredButton("send-button"),
  resultBanner: requiredElement("result-banner"),
  statusSequence: requiredElement("status-sequence"),
  statusState: requiredElement("status-state"),
  statusError: requiredElement("status-error"),
  packetLog: requiredElement("packet-log"),
  clearLogButton: requiredButton("clear-log-button"),
};

/** @type {BluetoothDevice | null} */
let selectedDevice = null;
/** @type {BluetoothRemoteGATTCharacteristic | null} */
let commandCharacteristic = null;
/** @type {BluetoothRemoteGATTCharacteristic | null} */
let statusCharacteristic = null;
/** @type {{ sequence: number, accepted: boolean } | null} */
let pendingCommand = null;
/** @type {number | null} */
let pendingCommandTimeout = null;

const storedSequence = Number.parseInt(localStorage.getItem("voxa-ble-next-sequence") ?? "1", 10);
elements.sequence.value = Number.isInteger(storedSequence) && storedSequence >= 1 && storedSequence <= 65_535
  ? String(storedSequence)
  : "1";

elements.findButton.addEventListener("click", findAndConnect);
elements.broadScanButton.addEventListener("click", findAnyDevice);
elements.reconnectButton.addEventListener("click", reconnectSelectedDevice);
elements.disconnectButton.addEventListener("click", disconnect);
elements.sendButton.addEventListener("click", sendCommand);
elements.clearLogButton.addEventListener("click", () => {
  elements.packetLog.replaceChildren();
  addLog("Info", "Packet log cleared.", "neutral");
});

showCompatibility();
setConnection("Not connected", "Power the Nano, then use Chrome’s chooser.", "idle");
addLog("Info", "Ready. No Bluetooth request has been made.", "neutral");

async function findAndConnect() {
  await selectAndConnect({ filters: [{ services: [SERVICE_UUID] }] });
}

async function findAnyDevice() {
  await selectAndConnect({ acceptAllDevices: true, optionalServices: [SERVICE_UUID] });
}

/** @param {RequestDeviceOptions} options */
async function selectAndConnect(options) {
  if (!("bluetooth" in navigator)) {
    showResult("Desktop Chrome is required. Safari and iPhone browsers cannot run this test.", "failure");
    return;
  }

  setConnection("Opening device chooser", "Select the device named Voxa Cue.", "working");
  try {
    const device = await navigator.bluetooth.requestDevice(options);
    if (selectedDevice !== null) {
      selectedDevice.removeEventListener("gattserverdisconnected", handleDisconnect);
    }
    selectedDevice = device;
    selectedDevice.addEventListener("gattserverdisconnected", handleDisconnect);
    elements.deviceName.textContent = device.name ?? "Unnamed BLE device";
    elements.deviceID.textContent = device.id;
    elements.reconnectButton.disabled = false;
    await connectToSelectedDevice();
  } catch (error) {
    handleBluetoothError(error, "Device selection failed");
  }
}

async function reconnectSelectedDevice() {
  if (selectedDevice === null) {
    showResult("Choose a device first.", "failure");
    return;
  }
  try {
    await connectToSelectedDevice();
  } catch (error) {
    handleBluetoothError(error, "Reconnection failed");
  }
}

async function connectToSelectedDevice() {
  const device = selectedDevice;
  if (device === null || device.gatt === undefined) {
    throw new Error("The selected device does not expose a Bluetooth GATT server.");
  }

  resetCharacteristics();
  setConnection("Connecting", `Opening a GATT connection to ${device.name ?? "the selected device"}.`, "working");
  const server = await device.gatt.connect();

  setConnection("Finding Voxa Cue service", SERVICE_UUID, "working");
  const service = await server.getPrimaryService(SERVICE_UUID);
  commandCharacteristic = await service.getCharacteristic(COMMAND_UUID);
  statusCharacteristic = await service.getCharacteristic(STATUS_UUID);

  statusCharacteristic.addEventListener("characteristicvaluechanged", handleStatusNotification);
  await statusCharacteristic.startNotifications();
  const initialStatus = await statusCharacteristic.readValue();
  receiveStatus(initialStatus, "Initial read");

  setConnection("Connected", "Notifications are active and commands can be written.", "ready");
  elements.findButton.disabled = true;
  elements.broadScanButton.disabled = true;
  elements.reconnectButton.disabled = true;
  elements.disconnectButton.disabled = false;
  elements.sendButton.disabled = false;
  showResult("BLE connected. Send a soft test command next.", "success");
  addLog("Connected", `${device.name ?? "Device"} exposed BLE protocol v1.`, "success");
}

function disconnect() {
  if (selectedDevice?.gatt?.connected === true) {
    selectedDevice.gatt.disconnect();
  } else {
    handleDisconnect(null);
  }
}

/** @param {Event | null} event */
function handleDisconnect(event) {
  if (event !== null && event.target !== selectedDevice) {
    return;
  }
  resetCharacteristics();
  setConnection("Disconnected", "The Nano may have lost power or ended the GATT connection.", "idle");
  elements.findButton.disabled = false;
  elements.broadScanButton.disabled = false;
  elements.reconnectButton.disabled = selectedDevice === null;
  elements.disconnectButton.disabled = true;
  elements.sendButton.disabled = true;
  showResult("Disconnected. Power-cycle the Nano if reconnecting fails.", "neutral");
  addLog("Disconnected", "GATT connection closed.", "neutral");
}

async function sendCommand() {
  if (commandCharacteristic === null) {
    showResult("Connect to Voxa Cue before sending a command.", "failure");
    return;
  }

  try {
    const sequence = Number.parseInt(elements.sequence.value, 10);
    const packet = encodeCommand({
      sequence,
      pattern: Number.parseInt(elements.pattern.value, 10),
      intensity: Number.parseInt(elements.intensity.value, 10),
      repeatCount: Number.parseInt(elements.repeatCount.value, 10),
    });

    elements.sendButton.disabled = true;
    pendingCommand = { sequence, accepted: false };
    pendingCommandTimeout = window.setTimeout(() => {
      if (pendingCommand?.sequence !== sequence) return;
      pendingCommand = null;
      pendingCommandTimeout = null;
      elements.sendButton.disabled = commandCharacteristic === null;
      showResult("Timed out waiting for firmware status. The write connected, but no matching completion arrived.", "failure");
      addLog("Status timeout", `No terminal status for sequence ${sequence}.`, "failure");
    }, 8_000);
    showResult("Writing command; waiting for accepted and completed statuses…", "working");
    addLog("Write requested", formatHex(packet), "outbound");
    await commandCharacteristic.writeValueWithResponse(packet);
  } catch (error) {
    pendingCommand = null;
    clearPendingCommandTimeout();
    handleBluetoothError(error, "Command write failed");
    elements.sendButton.disabled = commandCharacteristic === null;
  }
}

/** @param {Event} event */
function handleStatusNotification(event) {
  const characteristic = /** @type {BluetoothRemoteGATTCharacteristic} */ (event.target);
  if (characteristic.value !== undefined) {
    receiveStatus(characteristic.value, "Notification");
  }
}

/**
 * @param {DataView} dataView
 * @param {string} source
 */
function receiveStatus(dataView, source) {
  const bytes = new Uint8Array(dataView.buffer, dataView.byteOffset, dataView.byteLength);
  addLog(source, formatHex(bytes), "inbound");
  try {
    const status = decodeStatus(bytes);
    elements.statusSequence.textContent = String(status.sequence);
    elements.statusState.textContent = status.stateLabel;
    elements.statusError.textContent = status.errorLabel;
    elements.firmware.textContent = status.firmware;

    const transition = correlateCommandStatus(pendingCommand, status);
    pendingCommand = transition.pending;
    switch (transition.event) {
      case "unsolicited":
        if (status.error === 0 && status.state !== 2) updateNextSequence(status.sequence);
        break;
      case "unrelated":
        showResult(`Received status for sequence ${status.sequence}; still waiting for sequence ${pendingCommand?.sequence ?? "—"}.`, "working");
        break;
      case "accepted":
        updateNextSequence(status.sequence);
        showResult("Command accepted. Waiting for the vibration to complete…", "working");
        break;
      case "completed":
        clearPendingCommandTimeout();
        updateNextSequence(status.sequence);
        showResult("Passed: the matching BLE command was accepted and completed.", "success");
        elements.sendButton.disabled = false;
        break;
      case "completedWithoutAccepted":
        clearPendingCommandTimeout();
        showResult("The completion packet arrived without a matching accepted packet. Retry before treating this as a pass.", "failure");
        elements.sendButton.disabled = false;
        break;
      case "rejected":
        clearPendingCommandTimeout();
        showResult(
          status.error === 3
            ? "BLE works, but the Nano cannot detect the DRV2605L haptic driver."
            : `Firmware rejected the command: ${status.errorLabel}.`,
          "failure",
        );
        elements.sendButton.disabled = false;
        break;
    }
  } catch (error) {
    handleBluetoothError(error, "Invalid status packet");
  }
}

function resetCharacteristics() {
  if (statusCharacteristic !== null) {
    statusCharacteristic.removeEventListener("characteristicvaluechanged", handleStatusNotification);
  }
  commandCharacteristic = null;
  statusCharacteristic = null;
  pendingCommand = null;
  clearPendingCommandTimeout();
}

/**
 * @param {unknown} error
 * @param {string} context
 */
function handleBluetoothError(error, context) {
  pendingCommand = null;
  clearPendingCommandTimeout();
  const explanation = explainBluetoothError(error);
  setConnection(context, explanation, "failure");
  showResult(explanation, "failure");
  addLog(context, explanation, "failure");
  elements.findButton.disabled = false;
  elements.broadScanButton.disabled = false;
  elements.reconnectButton.disabled = selectedDevice === null;
  elements.disconnectButton.disabled = selectedDevice?.gatt?.connected !== true;
  elements.sendButton.disabled = commandCharacteristic === null;
}

function clearPendingCommandTimeout() {
  if (pendingCommandTimeout === null) return;
  window.clearTimeout(pendingCommandTimeout);
  pendingCommandTimeout = null;
}

/** @param {number} completedSequence */
function updateNextSequence(completedSequence) {
  const nextSequence = completedSequence === 0 ? 1 : sequenceAfter(completedSequence);
  elements.sequence.value = String(nextSequence);
  localStorage.setItem("voxa-ble-next-sequence", String(nextSequence));
}

/** @param {unknown} error */
function explainBluetoothError(error) {
  if (error instanceof DOMException) {
    if (error.name === "NotFoundError") {
      return "No Voxa Cue device was selected or advertising. Confirm firmware is flashed, power is on, and the iPhone app is disconnected.";
    }
    if (error.name === "SecurityError") {
      return "Chrome blocked Bluetooth access. Use this localhost page and allow Chrome Bluetooth permission in macOS Settings.";
    }
    if (error.name === "NetworkError") {
      return "The device was visible but the GATT connection failed. Close the iPhone app, power-cycle the Nano, and retry nearby.";
    }
    return `${error.name}: ${error.message}`;
  }
  return error instanceof Error ? error.message : "An unknown Bluetooth error occurred.";
}

function showCompatibility() {
  const supported = "bluetooth" in navigator;
  const secure = window.isSecureContext;
  elements.compatibility.textContent = supported && secure
    ? "Desktop Chrome and localhost are ready for Web Bluetooth."
    : "Web Bluetooth is unavailable here. Open this page through localhost in desktop Chrome.";
  elements.compatibility.dataset.state = supported && secure ? "ready" : "failure";
  elements.findButton.disabled = !(supported && secure);
  elements.broadScanButton.disabled = !(supported && secure);
}

/**
 * @param {string} state
 * @param {string} detail
 * @param {"idle" | "working" | "ready" | "failure"} tone
 */
function setConnection(state, detail, tone) {
  elements.connectionState.textContent = state;
  elements.connectionDetail.textContent = detail;
  elements.connectionDot.dataset.state = tone;
}

/**
 * @param {string} message
 * @param {"neutral" | "working" | "success" | "failure"} tone
 */
function showResult(message, tone) {
  elements.resultBanner.textContent = message;
  elements.resultBanner.dataset.state = tone;
}

/**
 * @param {string} label
 * @param {string} message
 * @param {"neutral" | "success" | "failure" | "inbound" | "outbound"} tone
 */
function addLog(label, message, tone) {
  const item = document.createElement("li");
  const metadata = document.createElement("span");
  const payload = document.createElement("code");
  metadata.textContent = `${new Date().toLocaleTimeString()} · ${label}`;
  metadata.dataset.state = tone;
  payload.textContent = message;
  item.append(metadata, payload);
  elements.packetLog.prepend(item);
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
  if (!(element instanceof HTMLButtonElement)) throw new Error(`#${id} must be a button.`);
  return element;
}

/** @param {string} id */
function requiredSelect(id) {
  const element = requiredElement(id);
  if (!(element instanceof HTMLSelectElement)) throw new Error(`#${id} must be a select.`);
  return element;
}

/** @param {string} id */
function requiredInput(id) {
  const element = requiredElement(id);
  if (!(element instanceof HTMLInputElement)) throw new Error(`#${id} must be an input.`);
  return element;
}
