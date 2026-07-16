# Voxa Cue setup guide

This is the shortest path from a clean Mac to the real phone-to-wrist prototype. The live coaching loop needs no cloud service and no API key.

## 1. Install the toolchain

Required:

- macOS with Xcode 27 beta at `/Applications/Xcode-beta.app`
- an iPhone running iOS 26 or later for real speech and BLE testing
- Node.js 22 or later, pnpm 10.32.1, XcodeGen, and `uvx`
- Arduino Nano 33 IoT, DRV2605L breakout, 3 V LRA motor, and a data-capable Micro-USB cable

```sh
brew install node pnpm xcodegen
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Xcode may request its first-launch components and license acceptance. Complete those before running the repository checks.

## 2. Install and verify the repository

```sh
git clone https://github.com/amaar-mc/voxa-cue.git
cd voxa-cue
pnpm install --frozen-lockfile
pnpm verify
```

`pnpm verify` checks the strict TypeScript API, Swift packages and app, privacy manifest, and native plus Nano 33 IoT and Nano ESP32 firmware.

## 3. Run the app without the wearable

```sh
pnpm ios:generate
open ios/VoxaCue.xcodeproj
```

To keep the signing team across future XcodeGen runs, copy `ios/Config/Signing.xcconfig.example` to the ignored `ios/LocalSigning.xcconfig` and replace `YOUR_TEAM_ID` with the selected Apple development team ID.

In Xcode:

1. Select the `VoxaCue` scheme and a physical iPhone.
2. Connect and unlock the iPhone, trust the Mac, and enable Developer Mode if prompted.
3. Open the Voxa Cue target, choose **Signing & Capabilities**, and select your Apple development team with automatic signing.
4. Open **Product → Scheme → Edit Scheme → Run → Arguments** and make sure `-demoScenario` is absent for real recording. Add it only for a labeled software demo.
5. Press Run. Xcode signs, installs, and launches the app through the cable.
6. Allow microphone, speech-recognition, and Bluetooth permissions, then start a session and place the phone nearby.

The iPhone built-in microphone is enforced. Connecting a headset or changing the input route stops live analysis instead of silently analyzing the wrong microphone. Raw audio is discarded and never persisted.

For a repeatable command-line cable install after the phone appears in `xcrun devicectl list devices`, run:

```sh
pnpm ios:device-install -- PHYSICAL_DEVICE_ID DEVELOPMENT_TEAM_ID
```

That command generates the Xcode project, signs a Debug build, installs it, and launches `com.amaarmc.voxacue`. It cannot run until the iPhone is connected, trusted, and associated with the selected Apple development team.

## 4. Wire and flash the Cue Band

Disconnect power before wiring:

| Nano 33 IoT | DRV2605L | Connection |
| --- | --- | --- |
| `3V3` | `VIN` | Bench power |
| `GND` | `GND` | Common ground |
| `A4` | `SDA` | I2C data |
| `A5` | `SCL` | I2C clock |
| — | `OUT+`, `OUT-` | LRA motor leads |

Never connect the motor directly to a GPIO, 3V3, or GND. Then flash:

```sh
cd firmware/voxa-wearable
uvx --with pip platformio test -e native
uvx --with pip platformio run -e nano_33_iot
uvx --with pip platformio run -e nano_33_iot --target upload
uvx --with pip platformio device monitor --baud 115200
```

If upload-port discovery fails:

```sh
uvx --with pip platformio device list
uvx --with pip platformio run -e nano_33_iot --target upload --upload-port /dev/cu.usbmodemYOUR_PORT
```

Before the first BLE test, update the Nano 33 IoT NINA-W102 connectivity firmware to 3.0.0 or newer with Arduino IDE's Firmware Updater, then flash Voxa firmware again. The monitor must print `Voxa Cue firmware 1.0 ready`. Connect inside **Settings → Device Lab**; do not pair from iOS Bluetooth Settings. Send each of the six active test commands before presenting.

## 5. Optional AI coaching API

This service is not in the live haptic loop. It is used only for a post-session practice plan after the user explicitly confirms transcript upload.

Live transcription, filler detection, pace, timing, pitch, energy, cue selection, BLE, and session storage continue to work without it.

### Required values

| Value | Where it belongs | Purpose |
| --- | --- | --- |
| `OPENAI_API_KEY` | Vercel or `api/.env.local` only | Calls the OpenAI Responses API |
| `OPENAI_MODEL=gpt-5.6-luna` | Vercel or `api/.env.local` | Cost-sensitive structured coaching model |
| `VOXA_BUILD_ID` | Vercel or `api/.env.local` | Exposes the deployed revision in probes |
| `VOXA_DEMO_API_TOKEN` | Server and ignored `ios/Local.xcconfig` | Closed-demo bearer token; generate at least 32 random characters |
| `VOXA_API_BASE_URL` | Ignored `ios/Local.xcconfig` | HTTPS origin of the deployed API |

Create an OpenAI API key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys) and configure API billing separately from any ChatGPT subscription. Never put `OPENAI_API_KEY` in Xcode, Swift, firmware, Git, or the mobile app.

### Run the server locally

```sh
cp api/.env.example api/.env.local
openssl rand -hex 32
```

Paste the random output into `VOXA_DEMO_API_TOKEN`, add the server-side OpenAI key, then run:

```sh
pnpm api:dev
```

Local HTTP is useful for `curl` and API development. The app deliberately accepts only HTTPS API origins, so use a Vercel deployment for an iPhone-connected test.

### Deploy to Vercel

```sh
cd api
pnpm exec vercel login
pnpm exec vercel link
pnpm exec vercel env add OPENAI_API_KEY production
pnpm exec vercel env add OPENAI_MODEL production
pnpm exec vercel env add VOXA_BUILD_ID production
pnpm exec vercel env add VOXA_DEMO_API_TOKEN production
pnpm exec vercel --prod
```

Use `gpt-5.6-luna` for `OPENAI_MODEL`, the Git commit SHA for `VOXA_BUILD_ID`, and the same random demo token generated above. Verify the returned HTTPS host:

```sh
curl https://YOUR_DEPLOYMENT_HOST/livez
curl -H 'Authorization: Bearer YOUR_DEMO_TOKEN' https://YOUR_DEPLOYMENT_HOST/readyz
```

### Connect the Debug app to the API

```sh
cp ios/Config/BuildSettings.xcconfig.example ios/Local.xcconfig
```

Edit the ignored file:

```xcconfig
URL_SLASH = /
VOXA_API_BASE_URL = https:$(URL_SLASH)$(URL_SLASH)YOUR_DEPLOYMENT_HOST
VOXA_DEMO_API_TOKEN = YOUR_DEMO_TOKEN
```

Regenerate the project, run the Debug build, then open **Settings → Check AI coaching**. Release builds intentionally disable the shared demo-token API until it is replaced with user- or device-scoped production authentication.

## Current costs

| Component | Prototype cost |
| --- | --- |
| Apple on-device speech, DSP, analytics, and BLE | No per-minute API charge |
| OpenAI `gpt-5.6-luna` | $1 per 1M input tokens and $6 per 1M output tokens ([official pricing](https://developers.openai.com/api/docs/models)) |
| OpenAI free tier | Not supported for `gpt-5.6-luna`; API billing must be enabled |
| Example OpenAI request | 10,000 input + 2,000 output tokens costs about $0.022 |
| Vercel Hobby | $0/month for personal, non-commercial use; usage caps apply ([official pricing](https://vercel.com/pricing)) |
| Vercel Pro | $20/month with $20 usage credit for commercial/team use ([official pricing](https://vercel.com/pricing)) |
| Apple device testing | Free with an Apple Account and Personal Team |
| App Store/TestFlight distribution | Apple Developer Program is $99/year ([official membership details](https://developer.apple.com/programs/whats-included/)) |

OpenAI cost formula: `(input tokens × $1 + output tokens × $6) ÷ 1,000,000`. The live presentation path costs $0 because it never calls OpenAI.

## Final physical check

1. Run a 60-second session with airplane mode enabled and Bluetooth re-enabled; transcription, metrics, and haptics must still work after any required Apple speech assets have already downloaded.
2. Walk through each enabled cue and confirm one accepted and one completed BLE status.
3. Disconnect the band mid-session; recording must continue and reconnect must not replay stale cues.
4. Wear-test all intensities for 15 minutes and check heat, enclosure contact, and pattern clarity.
5. Keep `docs/BACKEND_AUDIT.md` release gates closed until public authentication, quotas, and rate limits are implemented.
