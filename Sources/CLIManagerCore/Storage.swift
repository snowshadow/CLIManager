import Foundation

public protocol ProjectRepository {
    func loadProjects() throws -> [Project]
    func saveProjects(_ projects: [Project]) throws
}

public protocol RuntimeStateStore {
    func loadStates() throws -> [UUID: RuntimeState]
    func saveStates(_ states: [UUID: RuntimeState]) throws
}

public enum StorageError: LocalizedError, Equatable {
    case invalidProjectName
    case invalidProjectPath
    case invalidStartCommand
    case duplicateProject

    public var errorDescription: String? {
        switch self {
        case .invalidProjectName:
            return "Project name cannot be empty."
        case .invalidProjectPath:
            return "Project path must exist and be a directory."
        case .invalidStartCommand:
            return "Start command cannot be empty."
        case .duplicateProject:
            return "A project with the same path and start command already exists."
        }
    }
}

public struct AppPaths: Sendable {
    public let root: URL

    public var projectsFile: URL { root.appendingPathComponent("projects.json") }
    public var runtimeStateFile: URL { root.appendingPathComponent("runtime_state.json") }
    public var logsDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }

    public init(root: URL = AppPaths.defaultRoot()) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("CLIManager", isDirectory: true)
    }
}

public final class JSONProjectRepository: ProjectRepository {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadProjects() throws -> [Project] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Project].self, from: data)
    }

    public func saveProjects(_ projects: [Project]) throws {
        try ensureParentDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projects)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureParentDirectory() throws {
        let dir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

public final class JSONRuntimeStateStore: RuntimeStateStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadStates() throws -> [UUID: RuntimeState] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([UUID: RuntimeState].self, from: data)
    }

    public func saveStates(_ states: [UUID: RuntimeState]) throws {
        try ensureParentDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(states)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureParentDirectory() throws {
        let dir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
