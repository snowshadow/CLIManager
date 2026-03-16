import CLIManagerCore
import Foundation
import Testing

@Suite("Project Import Support")
struct ProjectImportSupportTests {
    @Test("Infers swift run from Package.swift")
    func infersSwiftRun() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "import PackageDescription\n".write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let command = try ProjectCommandInferrer().inferStartCommand(projectDirectory: dir)
        #expect(command == "swift run")
    }

    @Test("Returns ambiguity when package.json exposes dev and start")
    func reportsAmbiguousNpmScripts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let packageJSON = """
        {
          "scripts": {
            "dev": "vite",
            "start": "node index.js"
          }
        }
        """
        try packageJSON.write(to: dir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let error = #expect(throws: ProjectImportError.self) {
            _ = try ProjectCommandInferrer().inferStartCommand(projectDirectory: dir)
        }
        #expect(error == .ambiguousStartCommand(["npm run dev", "npm start"]))
    }

    @Test("Validator rejects invalid directory and duplicate path plus command")
    func validatorRejectsInvalidInputs() throws {
        let validator = ProjectValidator()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let existing = [Project(name: "demo", path: dir.path, startCommand: "swift run")]

        #expect(throws: StorageError.invalidProjectPath) {
            try validator.validate(name: "demo", path: "/definitely/missing", startCommand: "swift run", in: [])
        }

        #expect(throws: StorageError.duplicateProject) {
            try validator.validate(name: "demo", path: dir.path, startCommand: "swift run", in: existing)
        }
    }
}
