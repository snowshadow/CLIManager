import CLIManagerCore
import SwiftUI

struct ContentView: View {
    @ObservedObject private var model: AppViewModel
    @State private var activeSheet: EditorSheet?

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
            }
        } detail: {
            if let project = model.projects.first(where: { $0.id == model.selectedProjectID }) {
                projectDetail(project)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "hammer")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Project Selected")
                        .font(.headline)
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
