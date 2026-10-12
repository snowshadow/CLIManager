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
        // Standard Homebrew prefix on Apple Silicon Macs; writable by admin users without sudo.
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true).appendingPathComponent("climanager")
    }

    public static func shellInitSnippet() -> String {
        // Ensures /opt/homebrew/bin is on PATH (standard Homebrew shell setup).
        #"eval "$(/opt/homebrew/bin/brew shellenv)""#
    }

    public func installCLI(linkURL: URL, targetExecutableURL: URL) throws -> CLIInstallResult {
        let target = targetExecutableURL.standardizedFileURL
        let link = linkURL.standardizedFileURL

        try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)

        // `fileExists(atPath:)` follows symlinks, so a dangling symlink would slip past
        // this check and make `createSymbolicLink` fail. Detect the link itself too.
        let existingLink = try? fileManager.destinationOfSymbolicLink(atPath: link.path)
        if existingLink != nil || fileManager.fileExists(atPath: link.path) {
            if let existing = existingLink {
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
