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
                    statusBadge(for: model.states[project.id]?.status ?? .stopped)
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
                        Task { await model.reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
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
    private func statusBadge(for status: RuntimeStatus) -> some View {
        switch status {
        case .running:
            Text("running").font(.caption).padding(4).background(.green.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 4))
        case .starting:
            Text("starting").font(.caption).padding(4).background(.yellow.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 4))
        case .failed:
            Text("failed").font(.caption).padding(4).background(.red.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 4))
        case .stopped:
            Text("stopped").font(.caption).padding(4).background(.gray.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 4))
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

    private let appPaths = AppPaths()

    private var importCommand: String {
        "CLIManagerCLI import --path /absolute/path/to/project"
    }

    private var packageCommand: String {
        "swift run --package-path /path/to/CLIManager CLIManagerCLI import --path /absolute/path/to/project"
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

            GroupBox("Official Import API") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If CLIManagerCLI is already installed or built:")
                        .font(.subheadline.weight(.medium))
                    commandRow(importCommand)

                    Text("If you are calling from the source checkout:")
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 4)
                    commandRow(packageCommand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Data Location") {
                VStack(alignment: .leading, spacing: 10) {
                    pathRow(title: "CLIManager Data Root", path: appPaths.root.path)
                    pathRow(title: "Projects File", path: appPaths.projectsFile.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Imported projects appear after a refresh if the app is already open.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(width: 720, height: 420)
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
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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
}
