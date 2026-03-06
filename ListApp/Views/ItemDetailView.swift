import SwiftUI
import Core

struct ItemDetailView: View {
    @Environment(AppState.self) private var appState
    let item: Item
    @State private var showEditSheet = false

    // Always read fresh from appState so toggling updates the view
    private var currentItem: Item {
        appState.items.first(where: { $0.id == item.id }) ?? item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch currentItem.type {
                case "book":
                    BookDetailContent(item: currentItem)
                case "movie":
                    MovieDetailContent(item: currentItem)
                default:
                    TodoDetailContent(item: currentItem) {
                        appState.toggleCompletion(for: currentItem)
                    }
                }
            }
        }
        .navigationTitle(currentItem.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.toggleCompletion(for: currentItem)
                } label: {
                    let done = currentItem.completed
                    switch currentItem.type {
                    case "movie":
                        Label(done ? "Watched" : "Mark Watched",
                              systemImage: done ? "eye.fill" : "eye")
                    case "book":
                        Label(done ? "Read" : "Mark Read",
                              systemImage: done ? "book.closed.fill" : "book.closed")
                    default:
                        Label(done ? "Done" : "Mark Done",
                              systemImage: done ? "checkmark.circle.fill" : "circle")
                    }
                }
                .foregroundStyle(currentItem.completed ? .green : Color.accentColor)
            }
            if currentItem.type == "todo" {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Edit") { showEditSheet = true }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditTodoView(item: currentItem)
                .environment(appState)
        }
    }
}

// MARK: - Book Detail

private struct BookDetailContent: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: item.completed ? "book.closed.fill" : "book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(item.completed ? .green : Color.accentColor)
                    .frame(width: 72, height: 72)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.title3.bold())
                    if case .text(let author) = item.properties["author"] {
                        Text(author).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if case .number(let rating) = item.properties["rating"] {
                        StarRatingView(rating: rating)
                    }
                    StatusBadge(completed: item.completed, completedLabel: "Read ✓", pendingLabel: "To Read")
                }
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            PropertiesSection(item: item, exclude: ["author", "rating"])
            if !item.tags.isEmpty { TagsSection(tags: item.tags) }
            MetadataSection(item: item)
        }
        .padding(.vertical)
    }
}

// MARK: - Movie Detail

private struct MovieDetailContent: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: item.completed ? "film.fill" : "film")
                    .font(.system(size: 48))
                    .foregroundStyle(item.completed ? .green : Color.accentColor)
                    .frame(width: 72, height: 72)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.title3.bold())
                    if case .text(let director) = item.properties["director"] {
                        Text("Dir. \(director)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if case .number(let year) = item.properties["year"] {
                        Text(String(format: "%.0f", year)).font(.caption).foregroundStyle(.secondary)
                    }
                    if case .number(let rating) = item.properties["rating"] {
                        StarRatingView(rating: rating)
                    }
                    StatusBadge(completed: item.completed, completedLabel: "Watched ✓", pendingLabel: "To Watch")
                }
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            PropertiesSection(item: item, exclude: ["director", "year", "rating"])
            if !item.tags.isEmpty { TagsSection(tags: item.tags) }
            MetadataSection(item: item)
        }
        .padding(.vertical)
    }
}

// MARK: - Todo Detail

private struct TodoDetailContent: View {
    let item: Item
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                // Tappable checkbox — calls onToggle
                Button(action: onToggle) {
                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(item.completed ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.completed ? "Completed" : "Not completed").font(.headline)
                    if case .date(let date) = item.properties["dueDate"] {
                        let overdue = date < Date() && !item.completed
                        Label(
                            "Due \(date.formatted(date: .abbreviated, time: .omitted))",
                            systemImage: "calendar"
                        )
                        .font(.caption).foregroundStyle(overdue ? .red : .secondary)
                    }
                }
                Spacer()
                if case .text(let priority) = item.properties["priority"] {
                    PriorityBadge(priority: priority)
                }
            }
            .padding()
            .background(item.completed ? Color.green.opacity(0.08) : Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            PropertiesSection(item: item, exclude: ["priority", "dueDate"])
            if !item.tags.isEmpty { TagsSection(tags: item.tags) }
            MetadataSection(item: item)
        }
        .padding(.vertical)
    }
}

// MARK: - Edit Todo Sheet

struct EditTodoView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let item: Item

    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: String  // "", "high", "medium", "low"
    @State private var tagsText: String  // comma-separated

    init(item: Item) {
        self.item = item
        _title = State(initialValue: item.title)

        if case .date(let d) = item.properties["dueDate"] {
            _hasDueDate = State(initialValue: true)
            _dueDate = State(initialValue: d)
        } else {
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: Date())
        }

        if case .text(let p) = item.properties["priority"] {
            _priority = State(initialValue: p)
        } else {
            _priority = State(initialValue: "")
        }

        _tagsText = State(initialValue: item.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("None").tag("")
                        Text("🔴 High").tag("high")
                        Text("🟠 Medium").tag("medium")
                        Text("🔵 Low").tag("low")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("work, project/alpha", text: $tagsText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Comma-separated. Use / for hierarchy, e.g. work/project")
                }
            }
            .navigationTitle("Edit Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        var updated = item
        updated.title = title.trimmingCharacters(in: .whitespaces)

        // Tags
        updated.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Properties
        var props = item.properties
        if hasDueDate {
            props["dueDate"] = .date(dueDate)
        } else {
            props.removeValue(forKey: "dueDate")
        }
        if priority.isEmpty {
            props.removeValue(forKey: "priority")
        } else {
            props["priority"] = .text(priority)
        }
        updated.properties = props

        appState.updateItem(updated)
        dismiss()
    }
}

// MARK: - Shared Components

private struct StatusBadge: View {
    let completed: Bool
    let completedLabel: String
    let pendingLabel: String
    var body: some View {
        Text(completed ? completedLabel : pendingLabel)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(completed ? Color.green.opacity(0.15) : Color.orange.opacity(0.12))
            .foregroundStyle(completed ? .green : .orange)
            .clipShape(Capsule())
    }
}

private struct StarRatingView: View {
    let rating: Double
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating ? "star.fill" : "star")
                    .foregroundStyle(.yellow).font(.caption)
            }
            Text(String(format: "%.1f", rating)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PriorityBadge: View {
    let priority: String
    var body: some View {
        let (color, icon): (Color, String) = priority == "high"
            ? (.red, "exclamationmark.triangle.fill")
            : priority == "medium" ? (.orange, "arrow.up") : (.blue, "arrow.down")
        Label(priority.capitalized, systemImage: icon)
            .font(.caption.bold()).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.1)).clipShape(Capsule())
    }
}

private struct TagsSection: View {
    let tags: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.headline).padding(.horizontal)
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { TagChipView(tag: $0) }
            }
            .padding(.horizontal)
        }
    }
}

private struct PropertiesSection: View {
    let item: Item
    var exclude: [String] = []
    private var pairs: [(String, PropertyValue)] {
        item.properties
            .filter { !exclude.contains($0.key) }
            .sorted { $0.key < $1.key }
    }
    var body: some View {
        if !pairs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Details").font(.headline).padding(.horizontal)
                VStack(spacing: 0) {
                    ForEach(pairs, id: \.0) { key, value in
                        HStack {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .foregroundStyle(.secondary)
                            Spacer()
                            propertyView(value)
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        Divider().padding(.leading)
                    }
                }
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
    }
    @ViewBuilder
    private func propertyView(_ value: PropertyValue) -> some View {
        switch value {
        case .text(let t): Text(t)
        case .number(let n):
            Text(String(format: n.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", n))
        case .date(let d): Text(d, style: .date)
        case .bool(let b):
            Image(systemName: b ? "checkmark" : "xmark").foregroundStyle(b ? .green : .red)
        }
    }
}

private struct MetadataSection: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File").font(.headline).padding(.horizontal)
            VStack(spacing: 0) {
                HStack {
                    Text("Source").foregroundStyle(.secondary)
                    Spacer()
                    Text(URL(fileURLWithPath: item.sourceFile).lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal).padding(.vertical, 10)
                Divider().padding(.leading)
                HStack {
                    Text("Created").foregroundStyle(.secondary)
                    Spacer()
                    Text(item.createdAt, style: .date)
                }
                .padding(.horizontal).padding(.vertical, 10)
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }
}
