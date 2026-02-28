import CLIManagerCore
import Foundation
import Testing

@Suite("ProjectService")
struct ProjectServiceTests {
    @Test("Create project validates and persists")
    func createProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let repoFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("projects.json")
        let repo = JSONProjectRepository(fileURL: repoFile)
        let service = ProjectService(repository: repo)

        let created = try service.addProject(
            name: "API",
            path: tempDir.path,
            startCommand: "swift run"
        )

        let loaded = try service.loadProjects()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == created.id)
    }

    @Test("Duplicate path and command is rejected")
    func duplicateProjectRejected() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let repoFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("projects.json")
        let repo = JSONProjectRepository(fileURL: repoFile)
        let service = ProjectService(repository: repo)

        _ = try service.addProject(name: "One", path: tempDir.path, startCommand: "npm run dev")

        #expect(throws: StorageError.duplicateProject) {
            _ = try service.addProject(name: "Two", path: tempDir.path, startCommand: "npm run dev")
        }
    }
}
