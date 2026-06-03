import CLIManagerCore
import Foundation

struct CLIArguments {
    let path: String
    let name: String?
    let command: String?
    let dryRun: Bool
}

struct CLIInstallArguments {
    let target: String?
}

enum CLIError: LocalizedError {
    case missingSubcommand
    case unsupportedSubcommand(String)
    case missingValue(String)
    case missingPath
    case unsupportedArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingSubcommand:
            return "Missing subcommand."
        case .unsupportedSubcommand(let command):
            return "Unsupported subcommand: \(command)"
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .missingPath:
            return "--path is required."
        case .unsupportedArgument(let arg):
            return "Unsupported argument: \(arg)"
        }
    }
}

func usage() -> String {
    """
    Usage:
      CLIManagerCLI import --path /absolute/project/path [--name "Project"] [--command "swift run"] [--dry-run]
      CLIManagerCLI install-cli [--target ~/bin/climanager]

    Subcommands:
      import       Register a local CLI project in CLIManager
      install-cli  Install the `climanager` shell command as a symlink
    """
}

func parseImportArguments(_ args: ArraySlice<String>) throws -> CLIArguments {
    var path: String?
    var name: String?
    var command: String?
    var dryRun = false

    var index = args.startIndex
    while index < args.endIndex {
        let arg = args[index]
        switch arg {
        case "--path":
            index = args.index(after: index)
            guard index < args.endIndex else { throw CLIError.missingValue("--path") }
            path = args[index]
        case "--name":
            index = args.index(after: index)
            guard index < args.endIndex else { throw CLIError.missingValue("--name") }
            name = args[index]
        case "--command":
            index = args.index(after: index)
            guard index < args.endIndex else { throw CLIError.missingValue("--command") }
            command = args[index]
        case "--dry-run":
            dryRun = true
        case "--help", "-h":
            print(usage())
            exit(0)
        default:
            throw CLIError.unsupportedArgument(arg)
        }
        index = args.index(after: index)
    }

    guard let path else { throw CLIError.missingPath }
    return CLIArguments(path: path, name: name, command: command, dryRun: dryRun)
}

func parseInstallArguments(_ args: ArraySlice<String>) throws -> CLIInstallArguments {
    var target: String?

    var index = args.startIndex
    while index < args.endIndex {
        let arg = args[index]
        switch arg {
        case "--target":
            index = args.index(after: index)
            guard index < args.endIndex else { throw CLIError.missingValue("--target") }
            target = args[index]
        case "--help", "-h":
            print(usage())
            exit(0)
        default:
            throw CLIError.unsupportedArgument(arg)
        }
        index = args.index(after: index)
    }

    return CLIInstallArguments(target: target)
}

func expandPath(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}

func normalizedDirectoryURL(_ path: String) -> URL {
    URL(fileURLWithPath: expandPath(path), isDirectory: true).standardizedFileURL
}

func encodeResult(_ result: ProjectImportResult) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    if let output = String(data: data, encoding: .utf8) {
        print(output)
    }
}

func encodeInstallResult(_ result: CLIInstallResult) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    if let output = String(data: data, encoding: .utf8) {
        print(output)
    }
}

func importProject(args: CLIArguments) throws {
    let projectURL = normalizedDirectoryURL(args.path)
    let normalizedPath = projectURL.path
    let projectName = args.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? args.name!.trimmingCharacters(in: .whitespacesAndNewlines)
        : projectURL.lastPathComponent

    let command = try {
        if let explicit = args.command?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        return try ProjectCommandInferrer().inferStartCommand(projectDirectory: projectURL)
    }()

    let paths = AppPaths()
    let repository = JSONProjectRepository(fileURL: paths.projectsFile)
    let validator = ProjectValidator()
    let existing = try repository.loadProjects()

    if let duplicate = existing.first(where: { $0.path == normalizedPath && $0.startCommand == command }) {
        try encodeResult(ProjectImportResult(action: .unchanged, project: duplicate, projectsFile: paths.projectsFile.path))
        return
    }

    try validator.validate(name: projectName, path: normalizedPath, startCommand: command, in: existing, excludingId: nil)

    if args.dryRun {
        let now = Date()
        let preview = Project(name: projectName, path: normalizedPath, startCommand: command, createdAt: now, updatedAt: now)
        try encodeResult(ProjectImportResult(action: .preview, project: preview, projectsFile: paths.projectsFile.path))
        return
    }

    let service = ProjectService(repository: repository)
    let created = try service.addProject(name: projectName, path: normalizedPath, startCommand: command)
    try encodeResult(ProjectImportResult(action: .created, project: created, projectsFile: paths.projectsFile.path))
}

func installCLI(args: CLIInstallArguments) throws {
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let targetURL = args.target.map { URL(fileURLWithPath: expandPath($0)) } ?? CLIInstaller.defaultInstallURL()
    let result = try CLIInstaller().installCLI(linkURL: targetURL, targetExecutableURL: executableURL)
    try encodeInstallResult(result)
}

func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let subcommand = args.first else {
        throw CLIError.missingSubcommand
    }

    switch subcommand {
    case "import":
        try importProject(args: try parseImportArguments(args.dropFirst()))
    case "install-cli":
        try installCLI(args: try parseInstallArguments(args.dropFirst()))
    case "--help", "-h":
        print(usage())
    default:
        throw CLIError.unsupportedSubcommand(subcommand)
    }
}

do {
    try main()
} catch {
    fputs(error.localizedDescription + "\n", stderr)
    exit(1)
}
