import CLIManagerCore
import Foundation
import Testing

@Suite("CLI Install Support")
struct CLIInstallSupportTests {
    @Test("Creates a new symlink for climanager")
    func createsSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let target = dir.appendingPathComponent("CLIManagerCLI")
        try "#!/bin/sh\n".write(to: target, atomically: true, encoding: .utf8)

        let link = dir.appendingPathComponent("bin/climanager")
        let result = try CLIInstaller().installCLI(linkURL: link, targetExecutableURL: target)

        #expect(result.action == .created)
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(destination == target.path)
    }

    @Test("Leaves existing matching symlink unchanged")
    func leavesMatchingSymlinkUnchanged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let target = dir.appendingPathComponent("CLIManagerCLI")
        try "#!/bin/sh\n".write(to: target, atomically: true, encoding: .utf8)

        let link = dir.appendingPathComponent("bin/climanager")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = try CLIInstaller().installCLI(linkURL: link, targetExecutableURL: target)
        #expect(result.action == .unchanged)
    }
}
