import CLIManagerCore
import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var model: AppViewModel
    @State private var activeSheet: EditorSheet?
    @State private var showingAutomationGuide = false

    private struct EditorSheet: Identifiable {
        let id = UUID()
        let project: Project?
    }

    init(model: AppViewModel) {
        self.model = model
    }

    var body: some View {
        NavigationSplitView {
            List(model.projects, selection: Binding(get: {
                model.selectedProjectID
            }, set: { newValue in
                model.select(projectID: newValue)
            })) { project in
                HStack {
                    VStack(alignment: .leading) {
                        Text(project.name).font(.headline)
                        Text(project.path).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusBadge(for: model.states[project.id] ?? RuntimeState(projectId: project.id))
                }
                .tag(project.id)
                .contextMenu {
                    Button("Edit") { activeSheet = EditorSheet(project: project) }
                    Button("Delete", role: .destructive) {
                        Task { await model.delete(projectID: project.id) }
                    }
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem {
                    Button {
                        activeSheet = EditorSheet(project: nil)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button {
                        Task { await model.forceExternalScan() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh project list and scan for externally running processes")
                }
                ToolbarItem {
                    Button {
                        showingAutomationGuide = true
                    } label: {
                        Label("Automation", systemImage: "terminal")
                    }
                }
            }
        } detail: {
            if let project = model.projects.first(where: { $0.id == model.selectedProjectID }) {
                projectDetail(project)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hammer")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Project Selected")
                        .font(.headline)
                    Text("Import projects from your terminal with CLIManagerCLI.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Automation Guide") {
                        showingAutomationGuide = true
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            ProjectEditorView(existing: sheet.project, onCancel: {
                activeSheet = nil
            }, onSave: { name, path, command in
                Task {
                    if var updated = sheet.project {
                        updated.name = name
                        updated.path = path
                        updated.startCommand = command
                        await model.updateProject(updated)
                    } else {
                        await model.createProject(name: name, path: path, command: command)
                    }
                    activeSheet = nil
                }
            })
        }
        .sheet(isPresented: $showingAutomationGuide) {
            AutomationGuideView()
        }
        .task {
            await model.bootstrap()
        }
        .alert("Error", isPresented: Binding(get: {
            model.errorMessage != nil
        }, set: { newValue in
            if !newValue { model.clearError() }
        }), actions: {
            Button("OK", role: .cancel) { model.clearError() }
        }, message: {
            Text(model.errorMessage ?? "Unknown error")
        })
    }

    @ViewBuilder
    private func statusBadge(for state: RuntimeState) -> some View {
        let label: String = {
            if state.startedExternally {
                return state.ownedByCLIManager ? "running" : "running (external)"
            }
            switch state.status {
            case .running: return "running"
            case .starting: return "starting"
            case .failed: return "failed"
            case .stopped: return "stopped"
            }
        }()
        HStack(spacing: 4) {
            if state.startedExternally && !state.ownedByCLIManager {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9))
            }
            Text(label).font(.caption)
        }
        .padding(4)
        .background(background(for: state))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func background(for state: RuntimeState) -> Color {
        switch state.status {
        case .running:
            if state.startedExternally && !state.ownedByCLIManager { return .blue.opacity(0.2) }
            return .green.opacity(0.2)
        case .starting: return .yellow.opacity(0.3)
        case .failed: return .red.opacity(0.2)
        case .stopped: return .gray.opacity(0.2)
        }
    }

    private func projectDetail(_ project: Project) -> some View {
        let state = model.states[project.id] ?? RuntimeState(projectId: project.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(project.name).font(.title2.bold())
                    Text(project.path).font(.subheadline).foregroundStyle(.secondary)
                    Text(project.startCommand).font(.caption).foregroundStyle(.secondary)
                    if state.startedExternally && !state.ownedByCLIManager {
                        HStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10))
                            Text("Process started externally — logs from this session are unavailable.")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                        .padding(.top, 2)
                    }
                }
                Spacer()
                if state.status == .running || state.status == .starting {
                    Button("Stop") {
                        Task { await model.stop(projectID: project.id) }
                    }
                } else {
                    Button("Start") {
                        Task { await model.start(project: project) }
                    }
                }
            }

            GroupBox("Logs") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.selectedLogs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }
}

private struct AutomationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var installStatus: String?
    @State private var installError: String?
    @State private var isInstalling = false

    private let appPaths = AppPaths()

    private var importCommand: String {
        "climanager import --path /absolute/path/to/project"
    }

    private var packageCommand: String {
        "swift run --package-path /path/to/CLIManager CLIManagerCLI import --path /absolute/path/to/project"
    }

    private var installCommand: String {
        "swift run --package-path /path/to/CLIManager CLIManagerCLI install-cli"
    }

    private var shellInitSnippet: String {
        CLIInstaller.shellInitSnippet()
    }

    private var installPath: String {
        CLIInstaller.defaultInstallURL().path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automation")
                        .font(.title2.bold())
                    Text("Register CLI projects without using the Add Project form.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Official Import API") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("If the `climanager` command is installed:")
                                .font(.subheadline.weight(.medium))
                            commandRow(importCommand)

                            Text("If you are calling from the source checkout:")
                                .font(.subheadline.weight(.medium))
                                .padding(.top, 4)
                            commandRow(packageCommand)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Install Command-Line Tool") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Install a user-level `climanager` command linked to the bundled CLI binary.")
                                .foregroundStyle(.secondary)
                            commandRow(installCommand)
                            HStack {
                                Button(isInstalling ? "Installing..." : "Install `climanager`") {
                                    installBundledCLI()
                                }
                                .disabled(isInstalling)
                                Button("Copy PATH Snippet") {
                                    copyToPasteboard(shellInitSnippet)
                                }
                                Spacer()
                            }
                            if let installStatus {
                                Text(installStatus)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Data Location") {
                        VStack(alignment: .leading, spacing: 10) {
                            pathRow(title: "Installed CLI Link", path: installPath)
                            pathRow(title: "CLIManager Data Root", path: appPaths.root.path)
                            pathRow(title: "Projects File", path: appPaths.projectsFile.path)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Imported projects appear automatically after external commands update projects.json.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 760, maxWidth: 860, minHeight: 560, idealHeight: 640, maxHeight: 760)
        .alert("Install Error", isPresented: Binding(get: {
            installError != nil
        }, set: { newValue in
            if !newValue { installError = nil }
        }), actions: {
            Button("OK", role: .cancel) { installError = nil }
        }, message: {
            Text(installError ?? "Unknown error")
        })
    }

    @ViewBuilder
    private func commandRow(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(command)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy Command") {
                    copyToPasteboard(command)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func pathRow(title: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(path)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy Path") {
                    copyToPasteboard(path)
                }
                Button("Reveal in Finder") {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        NSWorkspace.shared.open(url.deletingLastPathComponent())
                    }
                }
                Spacer()
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func installBundledCLI() {
        guard !isInstalling else { return }
        isInstalling = true
        installStatus = nil

        Task {
            do {
                let target = try bundledCLIURL()
                let result = try await Task.detached(priority: .userInitiated) {
                    try CLIInstaller().installCLI(linkURL: CLIInstaller.defaultInstallURL(), targetExecutableURL: target)
                }.value
                await MainActor.run {
                    installStatus = "\(result.action.rawValue.capitalized): \(result.linkPath)"
                    isInstalling = false
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }

    private func bundledCLIURL() throws -> URL {
        let candidates: [URL?] = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CLIManagerCLI"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("CLIManagerCLI"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/CLIManagerCLI")
        ]

        if let found = candidates.compactMap({ $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return found
        }

        throw NSError(domain: "CLIManagerApp", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not locate the bundled CLIManagerCLI executable."
        ])
    }
}
