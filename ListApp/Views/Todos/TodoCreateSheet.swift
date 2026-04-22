import SwiftUI
import Core

struct TodoCreateSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var dueDate: Date = .now
    @State private var hasDueDate: Bool = false
    @State private var priority: TodoPriority = .p4
    @State private var project: String = ""
    @State private var labels: String = ""
    @State private var subtasks: [String] = [""]
    @State private var linkedNote: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("What to do", text: $title).noAutocapitalization()
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section("Schedule") {
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate)
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(TodoPriority.allCases) { p in
                            Label(p.label, systemImage: "flag.fill").tag(p)
                        }
                    }
                }
                Section("Project & labels") {
                    TextField("Project (e.g. work)", text: $project).noAutocapitalization()
                    TextField("Labels, comma-separated", text: $labels).noAutocapitalization()
                }
                Section("Subtasks") {
                    ForEach(subtasks.indices, id: \.self) { i in
                        TextField("Subtask", text: Binding(
                            get: { subtasks[i] },
                            set: { subtasks[i] = $0 }
                        ))
                    }
                    Button("Add subtask") { subtasks.append("") }
                }
                Section("Link to note") {
                    TextField("Path to .md (optional)", text: $linkedNote).noAutocapitalization()
                }
            }
            .navigationTitle("New Todo").navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        var props: [String: PropertyValue] = [:]
        if hasDueDate { props["dueDate"] = .date(dueDate) }
        if priority != .p4 { props["priority"] = .text(priority.storageValue) }
        if !notes.isEmpty { props["notes"] = .text(notes) }
        let cleanedSubs = subtasks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !cleanedSubs.isEmpty {
            props["subtaskList"] = .text(cleanedSubs.joined(separator: "\n"))
            props["subtasks"] = .text("0/\(cleanedSubs.count)")
        }
        if !linkedNote.isEmpty { props["linkedNote"] = .text(linkedNote) }
        var tags: [String] = []
        let project = self.project.trimmingCharacters(in: .whitespaces)
        if !project.isEmpty { tags.append(project) }
        tags.append(contentsOf: labels.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        do {
            _ = try await appState.createTodo(title: title, tags: tags, properties: props)
            dismiss()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
