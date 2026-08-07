import CLIManagerCore
import AppKit
import Sparkle
import SwiftUI

// MARK: - Sparkle Update Support

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

// MARK: - App Entry

@main
struct CLIManagerApp: App {
    @StateObject private var model: AppViewModel
    private let updaterController: SPUStandardUpdaterController

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let paths = AppPaths()
        let repo = JSONProjectRepository(fileURL: paths.projectsFile)
        let stateStore = JSONRuntimeStateStore(fileURL: paths.runtimeStateFile)
        let logService = LogService(logsDirectory: paths.logsDirectory)
        let runtime = RuntimeService(stateStore: stateStore, logService: logService)
        let projectService = ProjectService(repository: repo)
        _model = StateObject(wrappedValue: AppViewModel(projectService: projectService, runtimeService: runtime, projectsFileURL: paths.projectsFile))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
