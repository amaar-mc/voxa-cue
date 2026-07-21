import SwiftUI
import VoxaCore

struct CoachChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool

    let snapshot: SavedPracticeRoadmap
    let sourceSessionName: String
    let isDemoMode: Bool

    @State private var draft = ""

    private let starterPrompts = [
        "Cut my filler words",
        "Plan a five-minute drill",
        "Improve my opening",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        conversationHeader

                        if model.coachMessages.isEmpty {
                            starterPromptList
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            ForEach(model.coachMessages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }

                        if model.isSendingCoachMessage {
                            HStack(spacing: 9) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(CueTheme.signal)
                                Text("Thinking")
                                    .font(.cueCaption)
                                    .foregroundStyle(CueTheme.secondaryInk)
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(CueTheme.surface)
                            .clipShape(Capsule())
                            .id("coach-thinking")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Cue is preparing a response")
                        }
                    }
                    .padding(.horizontal, CueTheme.Space.large)
                    .padding(.top, CueTheme.Space.medium)
                    .padding(.bottom, CueTheme.Space.large)
                }
                .background(CueTheme.canvas)
                .onChange(of: model.coachMessages.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: model.isSendingCoachMessage) { _, _ in
                    scrollToLatest(proxy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
            }
            .navigationTitle("Ask Cue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        model.clearCoachConversation()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            model.clearCoachConversation()
        }
    }

    private var conversationHeader: some View {
        PremiumCard(padding: 17) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: isDemoMode ? "testtube.2" : "lock.shield")
                        .accessibilityHidden(true)
                    Text(isDemoMode ? "Deterministic demo" : sourceSessionName)
                }
                .font(.cueCaption)
                .foregroundStyle(isDemoMode ? CueTheme.amber : CueTheme.signal)

                Text(snapshot.roadmap.nextSessionGoal.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(CueTheme.ink)
                Text("Ask about this roadmap or your measured delivery.")
                    .font(.cueCaption)
                    .foregroundStyle(CueTheme.secondaryInk)
            }
        }
    }

    private var starterPromptList: some View {
        VStack(alignment: .leading, spacing: 9) {
            CueSectionLabel(text: "Try asking", color: CueTheme.secondaryInk)
                .padding(.leading, 3)
            ForEach(starterPrompts, id: \.self) { prompt in
                Button {
                    send(prompt)
                } label: {
                    HStack(spacing: 10) {
                        Text(prompt)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(CueTheme.ink)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CueTheme.signal)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(CueTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous)
                            .stroke(CueTheme.border.opacity(0.68), lineWidth: 0.6)
                    }
                }
                .buttonStyle(SpringPressStyle())
                .disabled(model.isSendingCoachMessage)
            }
        }
    }

    private func messageBubble(_ message: CoachMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 48)
            }
            Text(message.content)
                .font(.cueBody)
                .foregroundStyle(CueTheme.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(message.role == .user ? CueTheme.signalSoft : CueTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous))
                .overlay {
                    if message.role == .assistant {
                        RoundedRectangle(cornerRadius: CueTheme.Radius.medium, style: .continuous)
                            .stroke(CueTheme.border.opacity(0.62), lineWidth: 0.6)
                    }
                }
            if message.role == .assistant {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.role == .user ? "You" : "Cue"): \(message.content)")
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your delivery", text: $draft, axis: .vertical)
                .font(.cueBody)
                .lineLimit(1...4)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit(sendDraft)
                .onChange(of: draft) { _, newValue in
                    if newValue.count > 1_000 {
                        draft = String(newValue.prefix(1_000))
                    }
                }

            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(CueTheme.actionFill)
                    .clipShape(Circle())
            }
            .buttonStyle(SpringPressStyle())
            .disabled(trimmedDraft.isEmpty || model.isSendingCoachMessage)
            .opacity(trimmedDraft.isEmpty || model.isSendingCoachMessage ? 0.42 : 1)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, CueTheme.Space.large)
        .padding(.vertical, 11)
        .background(CueTheme.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CueTheme.border.opacity(0.62))
                .frame(height: 0.6)
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendDraft() {
        let content = trimmedDraft
        guard !content.isEmpty, !model.isSendingCoachMessage else { return }
        draft = ""
        send(content)
    }

    private func send(_ content: String) {
        composerFocused = false
        Task { await model.sendCoachMessage(content) }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        let target: AnyHashable?
        if model.isSendingCoachMessage {
            target = "coach-thinking"
        } else {
            target = model.coachMessages.last?.id
        }
        guard let target else { return }
        withAnimation(CueMotion.quick(reduceMotion: reduceMotion)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}
