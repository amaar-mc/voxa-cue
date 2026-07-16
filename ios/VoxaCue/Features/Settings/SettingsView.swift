import SwiftUI
import VoxaCore
import VoxaRuntime

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedDocument: SettingsDocument?
    @State private var confirmDataDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                ScreenTitle(
                    eyebrow: "Your Cue",
                    title: "Settings",
                    subtitle: "Band, haptics, privacy, and local data."
                )
                bandCard
                hapticTestCard
                processingCard
                apiCard
                dataCard
                informationCard
                versionFooter
            }
            .padding(.horizontal, CueTheme.Space.large)
            .padding(.top, CueTheme.Space.medium)
            .padding(.bottom, 36)
        }
        .background(CueTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedDocument) { document in
            SettingsDocumentView(document: document)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            deletionDialogTitle,
            isPresented: $confirmDataDeletion,
            titleVisibility: .visible
        ) {
            Button(deletionActionTitle, role: .destructive) {
                model.clearLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionMessage)
        }
    }

    private var bandCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                bandHeader
                VoxaButton(
                    title: connectionButtonTitle,
                    symbol: isConnectionActive ? "xmark" : "dot.radiowaves.left.and.right",
                    style: isBandReady ? .secondary : .primary,
                    disabled: false,
                    action: connectionButtonAction
                )
            }
        }
    }

    private var hapticTestCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                hapticHeader
                Text("Tap a pattern to learn its rhythm.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                CueMetricGrid(spacing: 10) {
                    ForEach(CueKind.allCases, id: \.self) { cue in
                        hapticButton(
                            title: hapticTitle(for: cue),
                            symbol: hapticSymbol(for: cue),
                            kind: cue,
                            tint: hapticTint(for: cue)
                        )
                    }
                }
            }
        }
    }

    private func hapticButton(title: String, symbol: String, kind: CueKind, tint: Color) -> some View {
        Button {
            model.testCue(kind: kind, intensity: .medium)
        } label: {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 92 : 74)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.7)
            }
            .opacity(isBandReady ? 1 : 0.46)
        }
        .buttonStyle(SpringPressStyle())
        .disabled(!isBandReady)
        .accessibilityLabel("Send \(title.lowercased()) haptic test request")
        .accessibilityValue(isBandReady ? "Cue Band connected" : "Unavailable until Cue Band connects")
        .accessibilityHint("Confirm delivery by feeling the wristband. Band errors appear as an alert.")
    }

    private func hapticTitle(for cue: CueKind) -> String {
        switch cue {
        case .tooFast: "Slow down"
        case .tooSlow: "Speed up"
        case .fillerBurst: "Fillers"
        case .deckBehind: "Advance"
        case .time75: "75% time"
        case .time90: "90% time"
        case .time100: "Time up"
        }
    }

    private func hapticSymbol(for cue: CueKind) -> String {
        switch cue {
        case .tooFast: "hare"
        case .tooSlow: "tortoise"
        case .fillerBurst: "quote.bubble"
        case .deckBehind: "rectangle.stack.badge.play"
        case .time75, .time90, .time100: "timer"
        }
    }

    private func hapticTint(for cue: CueKind) -> Color {
        switch cue {
        case .tooFast, .tooSlow: CueTheme.signal
        case .fillerBurst, .deckBehind: CueTheme.haptic
        case .time75, .time90, .time100: CueTheme.green
        }
    }

    private var processingCard: some View {
        PremiumCard(padding: 20) {
            HStack(alignment: .top, spacing: 15) {
                SectionMark(assetName: "OnDevicePrivacy", size: 58)
                VStack(alignment: .leading, spacing: 8) {
                    CueSectionLabel(text: "Privacy", color: CueTheme.green)
                    Text("Live analysis stays on this iPhone and raw audio is discarded. AI coaching is sent only after you confirm.")
                        .font(.cueBody)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var apiCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                apiHeader
                Text(apiStatusDetail)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(2)
                if isAPIConfigured, !model.demoMode {
                    VoxaAsyncButton(
                        title: "Check AI coaching",
                        loadingTitle: "Checking…",
                        symbol: "arrow.clockwise",
                        isLoading: model.coachingAPIState == .checking,
                        action: { Task { await model.checkCoachingAPI() } }
                    )
                }
            }
        }
    }

    private var dataCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                sectionLabel(title: "Local data", symbol: "internaldrive", tint: CueTheme.signal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(dataCountLabel)
                        .font(.cueBody.weight(.semibold))
                        .foregroundStyle(CueTheme.ink)
                    Text(localDataDescription)
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(role: .destructive) {
                    confirmDataDeletion = true
                } label: {
                    Label(deletionButtonTitle, systemImage: "trash")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CueTheme.red)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(CueTheme.red.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous)
                                .stroke(CueTheme.red.opacity(0.16), lineWidth: 0.7)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: CueTheme.Radius.small, style: .continuous))
                }
                .buttonStyle(SpringPressStyle())
                .disabled(model.sessions.isEmpty && model.insightBySession.isEmpty)
                .opacity(model.sessions.isEmpty && model.insightBySession.isEmpty ? 0.45 : 1)
            }
        }
    }

    private var informationCard: some View {
        PremiumCard(padding: 8) {
            VStack(spacing: 0) {
                documentButton(.privacy)
                Divider().padding(.leading, 50).overlay(CueTheme.border)
                documentButton(.terms)
                Divider().padding(.leading, 50).overlay(CueTheme.border)
                documentButton(.support)
            }
        }
    }

    private func documentButton(_ document: SettingsDocument) -> some View {
        Button {
            presentedDocument = document
        } label: {
            HStack(spacing: 14) {
                Image(systemName: document.symbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(CueTheme.signal)
                    .frame(width: 28, height: 28)
                Text(document.title)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CueTheme.secondaryInk.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(SpringPressStyle())
    }

    private var versionFooter: some View {
        VStack(spacing: 6) {
            CueWordmark(compact: true)
            Text("Voxa Cue \(appVersion) (\(buildNumber))")
                .font(.cueCaption.monospacedDigit())
                .foregroundStyle(CueTheme.secondaryInk)
            Text("Discreet guidance. Confident delivery.")
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func sectionLabel(title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(.caption2, design: .rounded, weight: .bold))
            CueSectionLabel(text: title, color: tint)
        }
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private var bandHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                connectionGlyph
                connectionText
            }
        } else {
            HStack(spacing: 14) {
                connectionGlyph
                connectionText
                Spacer(minLength: 8)
                connectionIndicator
            }
        }
    }

    private var connectionGlyph: some View {
        SectionMark(assetName: "HapticBand", size: 58)
        .accessibilityHidden(true)
    }

    private var connectionText: some View {
        VStack(alignment: .leading, spacing: 4) {
            CueSectionLabel(text: "Cue Band", color: CueTheme.signal)
            Text(model.connectionState.label)
                .font(.cueSection)
                .foregroundStyle(CueTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(connectionDetail)
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionIndicator: some View {
        Circle()
            .fill(connectionColor)
            .frame(width: 8, height: 8)
            .shadow(color: connectionColor.opacity(0.35), radius: 6)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var hapticHeader: some View {
        let title = VStack(alignment: .leading, spacing: 5) {
            CueSectionLabel(text: "Haptic language", color: CueTheme.signal)
            Text("Preview coaching patterns")
                .font(.cueSection)
                .foregroundStyle(CueTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        let status = StatusPill(
            label: isBandReady ? "Band connected" : "Connect first",
            symbol: isBandReady ? "checkmark" : "link",
            color: isBandReady ? CueTheme.green : CueTheme.secondaryInk
        )

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                title
                status
            }
        } else {
            HStack(alignment: .top) {
                title
                Spacer(minLength: 8)
                status
            }
        }
    }

    @ViewBuilder
    private var apiHeader: some View {
        let label = sectionLabel(title: "AI coaching", symbol: "sparkles", tint: CueTheme.signal)
        let status = StatusPill(
            label: apiStatusLabel,
            symbol: apiStatusSymbol,
            color: apiStatusColor
        )

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                label
                status
            }
        } else {
            HStack {
                label
                Spacer(minLength: 8)
                status
            }
        }
    }

    private var appConfiguration: AppConfiguration {
        AppConfiguration(bundle: .main, arguments: ProcessInfo.processInfo.arguments)
    }

    private var dataCountLabel: String {
        if model.demoMode {
            return "\(model.sessions.count) demo \(model.sessions.count == 1 ? "session" : "sessions")"
        }
        if model.usesTemporaryRecoveryStorage {
            return "\(model.sessions.count) temporary \(model.sessions.count == 1 ? "session" : "sessions")"
        }
        return "\(model.sessions.count) saved \(model.sessions.count == 1 ? "session" : "sessions")"
    }

    private var localDataDescription: String {
        if model.demoMode {
            return "Deterministic fixtures held only for this demo run"
        }
        if model.usesTemporaryRecoveryStorage {
            return "Persistent history is unavailable in this recovery launch. Clearing here affects temporary sessions only; deleting the app removes the unavailable store."
        }
        return "Transcripts, metrics, cue history, checkpoint outcomes, and generated insights"
    }

    private var deletionDialogTitle: String {
        if model.demoMode { return "Clear demo data?" }
        if model.usesTemporaryRecoveryStorage { return "Clear temporary session data?" }
        return "Delete all local Voxa Cue data?"
    }

    private var deletionActionTitle: String {
        if model.demoMode { return "Clear demo data" }
        if model.usesTemporaryRecoveryStorage { return "Clear temporary sessions" }
        return "Delete sessions and insights"
    }

    private var deletionButtonTitle: String {
        if model.demoMode { return "Clear demo data" }
        if model.usesTemporaryRecoveryStorage { return "Clear temporary data" }
        return "Delete all local data"
    }

    private var deletionMessage: String {
        if model.demoMode {
            return "This removes the deterministic session and coaching fixtures from this demo run."
        }
        if model.usesTemporaryRecoveryStorage {
            return "This clears only sessions created during this recovery launch. It cannot modify the unavailable persistent store; delete Voxa Cue from the iPhone to remove that store."
        }
        return "This permanently removes transcripts, metrics, cue history, checkpoint outcomes, and AI coaching stored by Voxa Cue on this phone."
    }

    private var isAPIConfigured: Bool {
        appConfiguration.demoAPIIsAvailable
    }

    private var apiStatusLabel: String {
        if model.demoMode { return "Demo mode" }
        return switch model.coachingAPIState {
        case .localOnly: "Local only"
        case .configured: "Not checked"
        case .checking: "Checking"
        case .ready: "Ready"
        case .unavailable: "Needs attention"
        }
    }

    private var apiStatusSymbol: String {
        if model.demoMode { return "testtube.2" }
        return switch model.coachingAPIState {
        case .localOnly: "iphone"
        case .configured: "questionmark.circle.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var apiStatusColor: Color {
        if model.demoMode { return CueTheme.signal }
        return switch model.coachingAPIState {
        case .localOnly: CueTheme.secondaryInk
        case .configured, .checking: CueTheme.signal
        case .ready: CueTheme.green
        case .unavailable: CueTheme.red
        }
    }

    private var apiStatusDetail: String {
        if model.demoMode {
            return "Uses labeled fixtures; no network request."
        }
        switch model.coachingAPIState {
        case .localOnly:
            return "Live coaching stays local. Optional AI insights are off."
        case .configured:
            return "Optional AI insights are configured but not checked."
        case .checking:
            return "Checking access. No presentation data is sent."
        case let .ready(build):
            return "Optional AI insights are available. Build \(build)."
        case let .unavailable(message):
            return message
        }
    }

    private var isBandReady: Bool {
        if case .ready = model.connectionState { return true }
        return false
    }

    private var isConnectionActive: Bool {
        switch model.connectionState {
        case .searching, .connecting, .discovering, .ready, .reconnecting:
            return true
        case .idle, .bluetoothUnavailable, .failed:
            return false
        }
    }

    private var connectionButtonTitle: String {
        if isBandReady { return "Disconnect Cue Band" }
        if isConnectionActive { return "Stop connection" }
        return "Connect Cue Band"
    }

    private var connectionButtonAction: () -> Void {
        isConnectionActive ? model.disconnectCueBand : model.connectCueBand
    }

    private var connectionColor: Color {
        switch model.connectionState {
        case .ready:
            CueTheme.green
        case .searching, .connecting, .discovering, .reconnecting:
            CueTheme.amber
        case .failed, .bluetoothUnavailable:
            CueTheme.red
        case .idle:
            CueTheme.secondaryInk
        }
    }

    private var connectionSymbol: String {
        switch model.connectionState {
        case .ready:
            "checkmark.circle.fill"
        case .searching, .connecting, .discovering, .reconnecting:
            "dot.radiowaves.left.and.right"
        case .bluetoothUnavailable:
            "antenna.radiowaves.left.and.right.slash"
        case .failed:
            "exclamationmark.triangle"
        case .idle:
            "applewatch"
        }
    }

    private var connectionDetail: String {
        switch model.connectionState {
        case let .ready(firmware):
            "Firmware \(firmware) • BLE protocol v1"
        case .idle:
            "Nearby band required for live vibration cues"
        case .bluetoothUnavailable:
            "Turn on Bluetooth in iPhone Settings, then retry"
        case .searching:
            "Looking for a nearby Voxa Cue wristband"
        case .connecting:
            "Opening a private Bluetooth connection"
        case .discovering:
            "Checking haptic command compatibility"
        case .reconnecting:
            "Restoring the most recent band connection"
        case let .failed(message):
            message
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

private enum SettingsDocument: String, Identifiable {
    case privacy
    case terms
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy"
        case .terms: "Prototype Terms"
        case .support: "Support"
        }
    }

    var eyebrow: String {
        switch self {
        case .privacy: "Your data"
        case .terms: "Use of Voxa Cue"
        case .support: "Help with the prototype"
        }
    }

    var symbol: String {
        switch self {
        case .privacy: "lock.shield"
        case .terms: "doc.text"
        case .support: "questionmark.circle"
        }
    }
}

private struct SettingsDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: SettingsDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenTitle(
                        eyebrow: document.eyebrow,
                        title: document.title,
                        subtitle: subtitle
                    )
                    ForEach(sections, id: \.title) { section in
                        PremiumCard(padding: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title)
                                    .font(.cueSection)
                                    .foregroundStyle(CueTheme.ink)
                                Text(section.body)
                                    .font(.cueBody)
                                    .foregroundStyle(CueTheme.secondaryInk)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.horizontal, CueTheme.Space.large)
                .padding(.vertical, CueTheme.Space.large)
            }
            .background(CueTheme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var subtitle: String {
        switch document {
        case .privacy:
            "A plain-language account of what the prototype measures, stores, and sends."
        case .terms:
            "The boundaries for using this educational product prototype."
        case .support:
            "Fast checks for the phone recorder, live speech coaching, and Cue Band."
        }
    }

    private var sections: [SettingsDocumentSection] {
        switch document {
        case .privacy:
            return [
                SettingsDocumentSection(
                    title: "During a session",
                    body: "Voxa Cue uses the iPhone microphone and Apple's on-device speech framework to create a live transcript and calculate speaking pace, filler words, elapsed time, talk ratio, pitch range, and energy range. The raw microphone recording is transient and is not retained by Voxa Cue."
                ),
                SettingsDocumentSection(
                    title: "Saved on this phone",
                    body: "Completed session summaries, finalized transcript text, metric samples, haptic cue events, checkpoint outcomes, and generated coaching insights are stored locally. Imported PowerPoint files, extracted slide bodies and notes, and raw audio are not retained. You can delete all local Voxa Cue data from Settings."
                ),
                SettingsDocumentSection(
                    title: "Optional remote features",
                    body: "When a coaching service is configured, importing a PowerPoint can send its extracted slide text and speaker notes to create timed checkpoints. The original file is not uploaded. Session information is never sent automatically: after a rehearsal, the final transcript, aggregate metrics, cue delivery history, and checkpoint outcomes leave the phone only when you explicitly confirm Generate AI coaching. Raw audio is never included."
                ),
                SettingsDocumentSection(
                    title: "AI provider retention",
                    body: "The Voxa Cue API validates the request, removes the app session identifier, and forwards only the required text to OpenAI. It requests no Responses API application-state storage. That setting is not a zero-retention guarantee: under default provider controls, abuse-monitoring logs may include prompts, responses, and derived metadata for up to 30 days unless the production project has approved Modified Abuse Monitoring or Zero Data Retention controls."
                ),
                SettingsDocumentSection(
                    title: "Cue Band connection",
                    body: "The app uses Bluetooth Low Energy to discover the wristband, send compact haptic commands, and receive command status and firmware version. Speech, transcripts, and presentation content are not sent to the wristband."
                )
            ]
        case .terms:
            return [
                SettingsDocumentSection(
                    title: "Educational prototype",
                    body: "Voxa Cue is an M&TSI product prototype intended for rehearsals and demonstrations. Features, compatibility, haptic patterns, and analytical results may change."
                ),
                SettingsDocumentSection(
                    title: "Use your judgment",
                    body: "Metrics and coaching are informational practice aids, not guarantees of presentation performance. Voxa Cue is not a medical, safety, accessibility, or emergency alert device. Do not use its vibration cues where distraction could create risk."
                ),
                SettingsDocumentSection(
                    title: "Your content",
                    body: "Only import presentations and record speech that you have permission to use. You remain responsible for the words, slide content, and other information you choose to process or submit for optional AI coaching."
                ),
                SettingsDocumentSection(
                    title: "Prototype availability",
                    body: "The team may pause the demo service, reset prototype data, or discontinue the prototype. Local data can be deleted at any time from this app's Settings screen."
                )
            ]
        case .support:
            return [
                SettingsDocumentSection(
                    title: "Cue Band will not connect",
                    body: "Charge and wake the wristband, keep it near the iPhone, and make sure Bluetooth is enabled. Disconnect any other phone using the band, then tap Connect Cue Band again. A connected band reports its firmware version in Settings."
                ),
                SettingsDocumentSection(
                    title: "Speech does not appear",
                    body: "Allow Microphone and Speech Recognition access, use an iPhone that supports the required on-device English speech model, and place the phone nearby with the microphone unobstructed. End the session and start again after changing permissions."
                ),
                SettingsDocumentSection(
                    title: "A vibration did not arrive",
                    body: "Open Settings, confirm the band shows Connected, then send a pattern test request and verify it on your wrist. During presentations, Voxa Cue intentionally applies persistence and cooldown rules so a brief metric change does not create a distracting alert."
                ),
                SettingsDocumentSection(
                    title: "Bring useful diagnostics",
                    body: "When reporting a prototype problem, include the iPhone model, iOS version, Cue Band firmware shown above, the step that failed, and whether the same action works in a new session. Do not include confidential transcript or slide content."
                )
            ]
        }
    }
}

private struct SettingsDocumentSection {
    let title: String
    let body: String
}
