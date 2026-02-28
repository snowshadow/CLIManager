import CLIManagerCore
import AppKit
import SwiftUI

struct ProjectEditorView: View {
    let existing: Project?
    let onCancel: () -> Void
    let onSave: (_ name: String, _ path: String, _ command: String) -> Void

    @State private var name: String
    @State private var path: String
    @State private var command: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case path
        case command
    }

    init(existing: Project?, onCancel: @escaping () -> Void, onSave: @escaping (_ name: String, _ path: String, _ command: String) -> Void) {
        self.existing = existing
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _path = State(initialValue: existing?.path ?? "")
        _command = State(initialValue: existing?.startCommand ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "New Project" : "Edit Project")
                .font(.title3.bold())

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .name)
            TextField("Path", text: $path)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .path)
            TextField("Start Command", text: $command)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .command)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(name, path, command)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.keyWindow?.makeFirstResponder(nil)
            focusedField = .name
        }
    }
}
