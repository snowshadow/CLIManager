import CLIManagerCore
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProjectID: UUID?
    @Published var states: [UUID: RuntimeState] = [:]
    @Published var selectedLogs: [String] = []
    @Published var errorMessage: String?

    private let projectService: ProjectService
    private let runtimeService: RuntimeService
    private var logTask: Task<Void, Never>?

    init(projectService: ProjectService, runtimeService: RuntimeService) {
        self.projectService = projectService
        self.runtimeService = runtimeService
    }

    func bootstrap() async {
        await runtimeService.startMonitoring()
        await runtimeService.reconcilePersistedStates()
        await reload()
    }

    func reload() async {
        do {
            projects = try projectService.loadProjects()
            states = await runtimeService.snapshotStates()

            if selectedProjectID == nil {
                selectedProjectID = projects.first?.id
            }
            if let selectedProjectID {
                subscribeLogs(for: selectedProjectID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createProject(name: String, path: String, command: String) async {
        do {
            _ = try projectService.addProject(name: name, path: path, startCommand: command)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProject(_ project: Project) async {
        do {
            try projectService.updateProject(project)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(projectID: UUID) async {
        do {
            try projectService.deleteProject(id: projectID)
            if let state = states[projectID], state.status == .running || state.status == .starting {
                try? await runtimeService.stop(projectId: projectID)
            }
            if selectedProjectID == projectID {
                selectedProjectID = nil
                selectedLogs = []
            }
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start(project: Project) async {
        do {
            try await runtimeService.start(project: project)
            await reloadStates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(projectID: UUID) async {
        do {
            try await runtimeService.stop(projectId: projectID)
            await reloadStates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(projectID: UUID?) {
        selectedProjectID = projectID
        selectedLogs = []
        guard let projectID else {
            logTask?.cancel()
            return
        }
        subscribeLogs(for: projectID)
    }

    func clearError() {
        errorMessage = nil
    }

    private func reloadStates() async {
        states = await runtimeService.snapshotStates()
    }

    private func subscribeLogs(for projectID: UUID) {
        logTask?.cancel()
        logTask = Task {
            let stream = await runtimeService.subscribeLogs(projectId: projectID)
            selectedLogs = []
            for await line in stream {
                guard !Task.isCancelled else { break }
                selectedLogs.append(line)
                if selectedLogs.count > 500 {
                    selectedLogs.removeFirst(selectedLogs.count - 500)
                }
            }
        }
    }
}
