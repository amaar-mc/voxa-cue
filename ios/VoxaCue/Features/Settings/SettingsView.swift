import SwiftUI
import VoxaCore
import VoxaRuntime

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var presentedDocument: SettingsDocument?
    @State private var confirmDataDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CueTheme.Space.large) {
                ScreenTitle(
                    eyebrow: "Your Cue",
                    title: "Settings",
                    subtitle: "Connect the wristband, verify feedback, and control what stays on your phone."
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
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(connectionColor.opacity(0.11))
                        Image(systemName: connectionSymbol)
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(connectionColor)
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CUE BAND")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(CueTheme.violet)
                        Text(model.connectionState.label)
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                        Text(connectionDetail)
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    Spacer()
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: connectionColor.opacity(0.35), radius: 6)
                        .accessibilityHidden(true)
                }
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
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("HAPTIC LANGUAGE")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(CueTheme.violet)
                        Text("Feel each coaching cue")
                            .font(.cueSection)
                            .foregroundStyle(CueTheme.ink)
                    }
                    Spacer()
                    StatusPill(
                        label: isBandReady ? "Ready" : "Connect first",
                        symbol: isBandReady ? "checkmark" : "link",
                        color: isBandReady ? CueTheme.green : CueTheme.secondaryInk
                    )
                }
                Text("The patterns are distinct from normal phone notifications, so you can react without looking down.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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
            .frame(height: 74)
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
        .accessibilityLabel("Test \(title.lowercased()) haptic")
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
        case .tooFast, .tooSlow: CueTheme.violet
        case .fillerBurst, .deckBehind: CueTheme.amber
        case .time75, .time90, .time100: CueTheme.green
        }
    }

    private var processingCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel(title: "PRIVACY BY DEFAULT", symbol: "lock.shield", tint: CueTheme.green)
                privacyRow(
                    title: "Live analysis stays on iPhone",
                    detail: "Speech recognition, pace, fillers, timing, pitch, and energy are calculated during the session on this phone.",
                    symbol: "iphone"
                )
                Divider().overlay(CueTheme.border)
                privacyRow(
                    title: "Raw audio is discarded",
                    detail: "Voxa Cue does not save or upload the microphone recording. Local history contains finalized text and measurements only.",
                    symbol: "waveform.slash"
                )
                Divider().overlay(CueTheme.border)
                privacyRow(
                    title: "AI coaching is opt-in",
                    detail: "The final transcript, aggregate metrics, cue delivery history, and checkpoint outcomes leave the phone only after you confirm Generate AI coaching.",
                    symbol: "hand.raised"
                )
            }
        }
    }

    private var apiCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    sectionLabel(title: "COACHING API", symbol: "sparkles", tint: CueTheme.violet)
                    Spacer()
                    StatusPill(
                        label: apiStatusLabel,
                        symbol: apiStatusSymbol,
                        color: apiStatusColor
                    )
                }
                Text(apiStatusDetail)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(3)
                if let host = appConfiguration.apiBaseURL?.host, isAPIConfigured {
                    Label(host, systemImage: "server.rack")
                        .font(.cueCaption)
                        .foregroundStyle(CueTheme.ink)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var dataCard: some View {
        PremiumCard(padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                sectionLabel(title: "LOCAL DATA", symbol: "internaldrive", tint: CueTheme.violet)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dataCountLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(CueTheme.ink)
                        Text(localDataDescription)
                            .font(.cueCaption)
                            .foregroundStyle(CueTheme.secondaryInk)
                    }
                    Spacer()
                }
                Button(role: .destructive) {
                    confirmDataDeletion = true
                } label: {
                    Label(deletionButtonTitle, systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(CueTheme.red)
                }
                .buttonStyle(SpringPressStyle())
                .disabled(model.sessions.isEmpty && model.insightBySession.isEmpty)
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
                    .foregroundStyle(CueTheme.violet)
                    .frame(width: 28, height: 28)
                Text(document.title)
                    .font(.cueBody)
                    .foregroundStyle(CueTheme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CueTheme.secondaryInk.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
        }
        .buttonStyle(SpringPressStyle())
    }

    private var versionFooter: some View {
        VStack(spacing: 6) {
            CueWordmark(compact: true)
            Text("Voxa Cue \(appVersion) (\(buildNumber))")
                .font(.cueCaption.monospacedDigit())
                .foregroundStyle(CueTheme.secondaryInk)
            Text("Your voice. Perfected.")
                .font(.cueCaption)
                .foregroundStyle(CueTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func sectionLabel(title: String, symbol: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.15)
            .foregroundStyle(tint)
    }

    private func privacyRow(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(CueTheme.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CueTheme.ink)
                Text(detail)
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
                    .lineSpacing(2)
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
        appConfiguration.apiBaseURL != nil && appConfiguration.demoAPIToken.count >= 32
    }

    private var apiStatusLabel: String {
        if model.demoMode { return "Demo mode" }
        return isAPIConfigured ? "Configured" : "Local only"
    }

    private var apiStatusSymbol: String {
        model.demoMode || isAPIConfigured ? "checkmark.circle.fill" : "iphone"
    }

    private var apiStatusColor: Color {
        model.demoMode || isAPIConfigured ? CueTheme.green : CueTheme.secondaryInk
    }

    private var apiStatusDetail: String {
        if model.demoMode {
            return "AI responses use the deterministic presentation scenario. No external coaching request is required."
        }
        if isAPIConfigured {
            return "The coaching endpoint is configured. Reachability is checked when you import a PowerPoint or approve an AI coaching request."
        }
        return "Live haptics and all session analytics still work locally. Add the API URL and demo token in the build configuration to enable AI coaching."
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
                    title: "Optional AI coaching",
                    body: "Voxa Cue does not send session information automatically. When you explicitly confirm Generate AI coaching, the final transcript, aggregate session metrics, cue delivery history, and checkpoint outcomes are sent to the configured Voxa Cue API. Raw audio is never included."
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
                    body: "Open Settings, confirm the band shows Connected, and try each haptic test. During presentations, Voxa Cue intentionally applies persistence and cooldown rules so a brief metric change does not create a distracting alert."
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
