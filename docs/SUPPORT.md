# Voxa Cue Support

Voxa Cue is currently a closed M&TSI prototype. Support is provided through the TestFlight invitation or M&TSI project channel used to distribute the build. The prototype has no account or production billing support. Internal Debug builds include a local StoreKit test and Demo Pro switch; neither can make a real charge, and Release builds expose no unlock path.

## Supported prototype configuration

- iPhone running iOS 26.0 or later
- Voxa Cue iPhone app version 1.0.0 (build 1)
- Seeed Studio XIAO nRF54L15 Sense running the Voxa Cue Zephyr firmware;
  Nano 33 IoT and Nano ESP32 remain supported development targets
- DRV2605L haptic driver and a 3 V ERM motor
- Optional HTTPS access to the deployed Voxa Cue API for post-session insights

No Raspberry Pi or external microphone is supported. Keep the iPhone screen open, place the phone near the presenter, and leave its built-in microphone unobstructed.

## Live session will not start

1. Open iOS Settings and confirm Voxa Cue has Microphone and Speech Recognition access.
2. Confirm the iPhone is running iOS 26 or later and has the English on-device speech assets available.
3. Close other apps using the microphone, reopen Voxa Cue, and start a new session.
4. Keep the app in the foreground for the full presentation.

If permission was denied, Voxa Cue stops before recording. It never silently uploads audio as a fallback.

## Cue Band will not connect or vibrate

1. Confirm the wearable is powered. For the XIAO, confirm its USB-C data cable
   exposes `Seeed Studio XIAO nrf54 CMSIS-DAP` in
   `uvx --with pip platformio device list` and reflash with
   `pnpm firmware:flash:xiao` if needed.
2. Open **Settings → Device Lab**, disconnect and reconnect the band. The advertised peripheral name is `Voxa Cue`.
3. If the band is missing, power-cycle the wearable and retry nearby with Bluetooth enabled.
4. If BLE connects but the motor does not run, inspect the DRV2605L wiring and
   startup output. A missing or faulted driver rejects commands instead of
   pretending they completed. After the wiring or power recovers, firmware
   retries detection once per second while idle; send a fresh test command.
5. Run the packet-level smoke test in the matching firmware README with a BLE inspector.

A Ready BLE connection is required to enter session setup and start a real
presentation. If the band disconnects after recording starts, on-device
recording and local analytics continue while haptic delivery reports failure.
`-demoScenario` loads labeled deterministic saved data for a UI walkthrough; it
does not bypass the Ready-band requirement or start a simulated live session.

For the XIAO, wire DRV2605L SDA to D4 (`P1.10`) and SCL to D5 (`P1.11`), then
wire red to D6, blue to D7, green to D8, and the optional active-buzzer signal
to D9. Use 3.3 V only, one 220–330 Ω resistor per RGB leg, and a transistor
stage for any buzzer that is not a 3.3 V-compatible high-impedance input. The
ERM motor must connect only to the DRV2605L output. The XIAO and Nano targets
share BLE v1, so changing the wearable does not require an iOS change.

Protocol v1 does not require pairing, bonding, or application-layer
authentication. Keep the prototype supervised, disconnect other BLE tools
before using the iPhone app, and do not treat its UUID or sequence number as a
security control.

## AI coaching is unavailable

Live coaching does not require AI or a network connection. The submitted
Release build disables the shared-token prototype API. For optional AI features
in an internal Debug build, confirm the build has a valid HTTPS
`VOXA_API_BASE_URL`, a matching bearer token of at least 32 characters, and a
reachable deployment. The API's authenticated `/health` endpoint must return
`status: ok`.

If the API is unavailable, post-session AI coaching remains unavailable while the transcript and metrics stay saved on the phone. Live coaching is unaffected.

## Remove local data

Open Voxa Cue Settings and use Clear Local Data to delete saved sessions, transcript segments, metrics, cue events, and generated insights. Uninstalling the app also removes its app-local storage. This action cannot be undone.

## Report a reproducible issue

Include the app version/build, iPhone model and iOS version, firmware version, whether `-demoScenario` was active, the exact action taken, and the visible error. Do not include a transcript, API token, OpenAI key, or other sensitive content unless the project team explicitly requests a safe test fixture.
