import CLIManagerCore
import Foundation
import Testing

@Suite("Storage")
struct StorageTests {
    @Test("Project repository save/load round trip")
    func projectRepositoryRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent("projects.json")
        let repo = JSONProjectRepository(fileURL: file)

        let project = Project(name: "demo", path: "/tmp", startCommand: "echo hi")
        try repo.saveProjects([project])
        let loaded = try repo.loadProjects()

        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "demo")
    }

    @Test("Runtime store save/load round trip")
    func runtimeStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent("runtime_state.json")
        let store = JSONRuntimeStateStore(fileURL: file)

        let id = UUID()
        let states = [id: RuntimeState(projectId: id, status: .running, pid: 123)]
        try store.saveStates(states)
        let loaded = try store.loadStates()

        #expect(loaded[id]?.status == .running)
        #expect(loaded[id]?.pid == 123)
    }
}
