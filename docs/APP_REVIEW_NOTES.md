# App Review Notes

## App identity

- Name: Voxa Cue
- Version: 1.0.0
- Build: 1
- Bundle identifier: `com.amaarmc.voxacue`
- Minimum OS: iOS 26.0
- Device family: iPhone

Voxa Cue is a presentation coaching app. It uses the iPhone microphone for
on-device speech analysis and sends discreet haptic cues over BLE to a required
Cue Band prototype during real sessions.

## Access

No sign-in, user account, production subscription, purchase, or in-app payment
exists in the submitted Release build. The local StoreKit configuration and
Demo Pro switch are Debug-only test paths and are absent from Release. Reviewers
do not need credentials. A connected Cue Band is required to enter session
setup and start a real recording. Saved sessions and local analytics remain
available without a current band connection. The submitted Release build does
not enable the shared-token prototype AI service.

## Reviewer walkthrough with a Cue Band

1. Launch the app and complete the four onboarding pages. Hardware connection
   does not block onboarding.
2. Power the supplied band, then use **Connect Cue Band** on Today. Wait for the
   connected state; do not pair it in iOS Bluetooth Settings.
3. Start a new session, enter a name, choose a target duration and pace range,
   and leave at least one cue enabled.
4. Tap **Begin presentation** and grant Microphone and Speech Recognition
   permission.
5. Speak for at least 30 seconds. The live view shows elapsed time, rolling
   pace, filler count, talk ratio, transcript progress, and any locally decided
   cue.
6. End the session and inspect the local summary, transcript, vocal ranges, and
   metrics.
7. Open Sessions and Insights to inspect saved local history. Open Settings to
   inspect privacy controls and clear local data.

If the band disconnects after a session starts, on-device recording and analysis
continue while haptic deliveries report failure. The `-demoScenario` launch
argument loads clearly labeled deterministic saved data for an attended UI
walkthrough. It does not bypass the Ready-band requirement or start a simulated
live recording.

## Permissions

- Microphone: captures the presenter's voice during an active session.
- Speech Recognition: produces an on-device, time-indexed transcript for metrics.
- Bluetooth: discovers the required Cue Band before a real session, writes
  haptic commands and bounded session-light timing state, and receives haptic
  acknowledgements.

Raw audio is processed transiently and is never saved or uploaded. The wearable receives only a six-byte physical haptic-pattern command and an optional three-byte session-light timing state; it never receives audio, presentation content, or transcript text.

The closed prototype's BLE protocol does not require pairing, bonding, or
application-layer authentication. Its UUIDs and sequence counter are not device
authentication, so another nearby central that knows the UUIDs could connect and
write commands. This transport requires authenticated device enrollment and
abuse limits before a public release.

## Network and AI behavior

Real-time transcription, metrics, cue selection, and BLE delivery run on the iPhone. Network access is not part of the live feedback loop.

In internal Debug builds configured with the optional prototype API,
post-session AI coaching sends the final transcript, aggregate metrics, and
cue-delivery history only after a confirmation dialog names the transmitted
data. The API rejects direct audio-shaped content, does not have an application database,
requests schema-constrained output, and sets OpenAI response storage to false.
Release builds intentionally disable this shared-token API path.

## Additional disclosures

- The app has no advertising, tracking, analytics SDK, social feed, user-generated public content, or background recording.
- The app declares no non-exempt encryption; it uses operating-system BLE and HTTPS networking.
- Pitch and energy ranges are described as acoustic measurements, not evaluations of identity, health, or disability.
- `-demoScenario` loads labeled deterministic saved data for an attended
  development UI walkthrough. It does not bypass the Ready-band requirement for
  a new session. App Review should follow the hardware walkthrough above for
  live functionality.

Public privacy policy, support, and terms URLs plus a stable review API deployment are required release inputs before an App Store submission. They are tracked in `docs/RELEASE_CHECKLIST.md`.
