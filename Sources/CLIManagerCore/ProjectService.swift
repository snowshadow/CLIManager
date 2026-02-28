import Foundation

public final class ProjectService {
    private let repository: ProjectRepository
    private let fileManager: FileManager

    public init(repository: ProjectRepository, fileManager: FileManager = .default) {
        self.repository = repository
        self.fileManager = fileManager
    }

    public func loadProjects() throws -> [Project] {
        try repository.loadProjects().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func addProject(name: String, path: String, startCommand: String) throws -> Project {
        var projects = try repository.loadProjects()
        let project = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines), path: path, startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines))
        try validate(project: project, in: projects, excludingId: nil)
        projects.append(project)
        try repository.saveProjects(projects)
        return project
    }

    public func updateProject(_ project: Project) throws {
        var projects = try repository.loadProjects()
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else {
            return
        }

        var updated = project
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.startCommand = updated.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()

        try validate(project: updated, in: projects, excludingId: updated.id)
        projects[idx] = updated
        try repository.saveProjects(projects)
    }

    public func deleteProject(id: UUID) throws {
        let projects = try repository.loadProjects().filter { $0.id != id }
        try repository.saveProjects(projects)
    }

    private func validate(project: Project, in existing: [Project], excludingId: UUID?) throws {
        if project.name.isEmpty {
            throw StorageError.invalidProjectName
        }
        if project.startCommand.isEmpty {
            throw StorageError.invalidStartCommand
        }

        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: project.path, isDirectory: &isDir) || !isDir.boolValue {
            throw StorageError.invalidProjectPath
        }

        let duplicate = existing.contains {
            $0.id != excludingId && $0.path == project.path && $0.startCommand == project.startCommand
        }
        if duplicate {
            throw StorageError.duplicateProject
        }
    }
}
