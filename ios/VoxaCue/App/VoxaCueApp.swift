import AVFoundation
import SwiftData
import SwiftUI
import VoxaRuntime

@main
@MainActor
struct VoxaCueApp: App {
    private struct DataStoreBootstrap {
        let dataStore: VoxaDataStore
        let warning: String?
    }

    private let dataStore: VoxaDataStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    init() {
        let configuration = AppConfiguration(bundle: .main, arguments: ProcessInfo.processInfo.arguments)
        let bootstrap = Self.makeDataStore(inMemory: configuration.demoMode)
        self.dataStore = bootstrap.dataStore
        let appModel = AppModel(
            dataStore: bootstrap.dataStore,
            speechPipeline: LiveSpeechPipeline(audioEngine: AVAudioEngine()),
            cueBandClient: CueBandClient(),
            apiClient: configuration.makeAPIClient(session: .shared),
            demoMode: configuration.demoMode,
            preferences: .standard
        )
        appModel.lastError = bootstrap.warning
        _model = State(
            initialValue: appModel
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(dataStore.container)
                .tint(CueTheme.violet)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .inactive, .background:
                model.handleSceneBecameInactive()
            case .active:
                break
            @unknown default:
                model.handleSceneBecameInactive()
            }
        }
    }

    private static func makeDataStore(inMemory: Bool) -> DataStoreBootstrap {
        do {
            return DataStoreBootstrap(
                dataStore: try VoxaDataStore(inMemory: inMemory),
                warning: nil
            )
        } catch {
            guard !inMemory else {
                fatalError("Voxa Cue could not initialize its temporary data store: \(error.localizedDescription)")
            }
            do {
                return DataStoreBootstrap(
                    dataStore: try VoxaDataStore(inMemory: true),
                    warning: "Local history could not be opened. This launch will use temporary storage without deleting the existing store."
                )
            } catch {
                fatalError("Voxa Cue could not initialize local storage: \(error.localizedDescription)")
            }
        }
    }
}
