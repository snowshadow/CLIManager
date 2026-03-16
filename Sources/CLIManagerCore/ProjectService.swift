import Foundation

public final class ProjectService {
    private let repository: ProjectRepository
    private let validator: ProjectValidator

    public init(repository: ProjectRepository, fileManager: FileManager = .default) {
        self.repository = repository
        self.validator = ProjectValidator(fileManager: fileManager)
    }

    public func loadProjects() throws -> [Project] {
        try repository.loadProjects().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func addProject(name: String, path: String, startCommand: String) throws -> Project {
        var projects = try repository.loadProjects()
        let project = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines), path: path, startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines))
        try validator.validate(name: project.name, path: project.path, startCommand: project.startCommand, in: projects, excludingId: nil)
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

        try validator.validate(name: updated.name, path: updated.path, startCommand: updated.startCommand, in: projects, excludingId: updated.id)
        projects[idx] = updated
        try repository.saveProjects(projects)
    }

    public func deleteProject(id: UUID) throws {
        let projects = try repository.loadProjects().filter { $0.id != id }
        try repository.saveProjects(projects)
    }
}
