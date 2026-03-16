import CLIManagerCore
import AppKit
import SwiftUI

@main
struct CLIManagerApp: App {
    @StateObject private var model: AppViewModel

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

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
    }
}
