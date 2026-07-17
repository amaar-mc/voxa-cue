import SwiftUI
import VoxaCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedVoxaOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.99)))
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
            }
        }
        .animation(CueMotion.settle(reduceMotion: reduceMotion), value: hasCompletedOnboarding)
        .background(CueTheme.canvas.ignoresSafeArea())
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack { TodayView() }
                .tag(AppModel.Tab.today)
                .tabItem { Label("Today", systemImage: "waveform") }
            NavigationStack { SessionsView() }
                .tag(AppModel.Tab.sessions)
                .tabItem { Label("Sessions", systemImage: "clock.arrow.circlepath") }
            NavigationStack { InsightsView() }
                .tag(AppModel.Tab.insights)
                .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationStack { SettingsView() }
                .tag(AppModel.Tab.settings)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .toolbarBackground(CueTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sensoryFeedback(.selection, trigger: model.selectedTab)
        .sheet(isPresented: $model.setupPresented, onDismiss: model.presentPendingSession) {
            SessionSetupView()
        }
        .fullScreenCover(item: $model.activeSession) { session in
            LiveSessionView(session: session)
        }
        .sheet(
            isPresented: Binding(
                get: { model.completedSummary != nil },
                set: { if !$0 { model.dismissCompletedSummary() } }
            )
        ) {
            if let summary = model.completedSummary {
                SessionSummaryView(summary: summary, dismissAction: { model.dismissCompletedSummary() })
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.selectedSummary != nil },
                set: { if !$0 { model.selectedSummary = nil } }
            )
        ) {
            if let summary = model.selectedSummary {
                SessionSummaryView(summary: summary, dismissAction: { model.selectedSummary = nil })
            }
        }
        .alert(
            "Couldn’t complete that",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
