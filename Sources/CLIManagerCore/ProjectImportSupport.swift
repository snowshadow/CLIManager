import Foundation

public enum ProjectImportAction: String, Codable, Sendable {
    case created
    case unchanged
    case preview
}

public struct ProjectImportResult: Codable, Sendable {
    public let action: ProjectImportAction
    public let project: Project
    public let projectsFile: String

    public init(action: ProjectImportAction, project: Project, projectsFile: String) {
        self.action = action
        self.project = project
        self.projectsFile = projectsFile
    }
}

public enum ProjectImportError: LocalizedError, Equatable, Sendable {
    case ambiguousStartCommand([String])
    case cannotInferStartCommand(String)

    public var errorDescription: String? {
        switch self {
        case .ambiguousStartCommand(let commands):
            return "Could not choose a single start command. Candidates: \(commands.joined(separator: ", "))"
        case .cannotInferStartCommand(let path):
            return "Could not infer a start command for \(path). Provide --command explicitly."
        }
    }
}

public final class ProjectValidator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func validate(name: String, path: String, startCommand: String, in existing: [Project], excludingId: UUID? = nil) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StorageError.invalidProjectName
        }
        if startCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StorageError.invalidStartCommand
        }

        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue {
            throw StorageError.invalidProjectPath
        }

        let duplicate = existing.contains {
            $0.id != excludingId && $0.path == path && $0.startCommand == startCommand
        }
        if duplicate {
            throw StorageError.duplicateProject
        }
    }
}

public struct ProjectCommandInferrer {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inferStartCommand(projectDirectory: URL) throws -> String {
        let heuristics: [[String]] = [
            packageJSONCommand(in: projectDirectory),
            makefileCommand(in: projectDirectory),
            fileManager.fileExists(atPath: projectDirectory.appendingPathComponent("Cargo.toml").path) ? ["cargo run"] : [],
            fileManager.fileExists(atPath: projectDirectory.appendingPathComponent("Package.swift").path) ? ["swift run"] : [],
            fileManager.fileExists(atPath: projectDirectory.appendingPathComponent("go.mod").path) ? ["go run ."] : [],
            denoCommand(in: projectDirectory),
            fileManager.fileExists(atPath: projectDirectory.appendingPathComponent("main.py").path) ? ["python main.py"] : []
        ]

        for commands in heuristics where !commands.isEmpty {
            if commands.count == 1 {
                return commands[0]
            }
            throw ProjectImportError.ambiguousStartCommand(commands)
        }

        throw ProjectImportError.cannotInferStartCommand(projectDirectory.path)
    }

    private func packageJSONCommand(in directory: URL) -> [String] {
        let file = directory.appendingPathComponent("package.json")
        guard
            let data = try? Data(contentsOf: file),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = json["scripts"] as? [String: Any]
        else {
            return []
        }

        var candidates: [String] = []
        if scripts["dev"] != nil { candidates.append("npm run dev") }
        if scripts["start"] != nil { candidates.append("npm start") }
        return candidates
    }

    private func makefileCommand(in directory: URL) -> [String] {
        let file = directory.appendingPathComponent("Makefile")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        var candidates: [String] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("dev:") { candidates.append("make dev") }
            if line.hasPrefix("run:") { candidates.append("make run") }
        }
        return candidates
    }

    private func denoCommand(in directory: URL) -> [String] {
        for filename in ["deno.json", "deno.jsonc"] {
            let file = directory.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: file) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let tasks = json["tasks"] as? [String: Any] else { continue }

            var commands: [String] = []
            if tasks["dev"] != nil { commands.append("deno task dev") }
            if tasks["start"] != nil { commands.append("deno task start") }
            return commands
        }

        return []
    }
}
