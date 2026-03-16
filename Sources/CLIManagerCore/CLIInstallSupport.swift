import Foundation

public enum CLIInstallAction: String, Codable, Sendable {
    case created
    case updated
    case unchanged
}

public struct CLIInstallResult: Codable, Sendable {
    public let action: CLIInstallAction
    public let linkPath: String
    public let targetPath: String
    public let shellInitSnippet: String

    public init(action: CLIInstallAction, linkPath: String, targetPath: String, shellInitSnippet: String) {
        self.action = action
        self.linkPath = linkPath
        self.targetPath = targetPath
        self.shellInitSnippet = shellInitSnippet
    }
}

public final class CLIInstaller {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public static func defaultInstallURL(fileManager: FileManager = .default) -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent("bin", isDirectory: true).appendingPathComponent("climanager")
    }

    public static func shellInitSnippet() -> String {
        #"export PATH="$HOME/bin:$PATH""#
    }

    public func installCLI(linkURL: URL, targetExecutableURL: URL) throws -> CLIInstallResult {
        let target = targetExecutableURL.standardizedFileURL
        let link = linkURL.standardizedFileURL

        try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: link.path) {
            if let existing = try? fileManager.destinationOfSymbolicLink(atPath: link.path) {
                let resolvedExisting = URL(fileURLWithPath: existing, relativeTo: link.deletingLastPathComponent())
                    .standardizedFileURL
                if resolvedExisting.path == target.path {
                    return CLIInstallResult(
                        action: .unchanged,
                        linkPath: link.path,
                        targetPath: target.path,
                        shellInitSnippet: Self.shellInitSnippet()
                    )
                }
            }
            try fileManager.removeItem(at: link)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
            return CLIInstallResult(
                action: .updated,
                linkPath: link.path,
                targetPath: target.path,
                shellInitSnippet: Self.shellInitSnippet()
            )
        }

        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        return CLIInstallResult(
            action: .created,
            linkPath: link.path,
            targetPath: target.path,
            shellInitSnippet: Self.shellInitSnippet()
        )
    }
}
