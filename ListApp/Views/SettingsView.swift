import SwiftUI
import Core

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTheme = "system"
    @State private var defaultDisplayStyle = DisplayStyle.list
    @State private var showFolderPicker = false
    @State private var vaultFolderName: String = {
        // Check if vault exists
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vault = docs.appendingPathComponent("ListAppVault")
        return FileManager.default.fileExists(atPath: vault.path) ? "ListAppVault" : "Not set"
    }()

    var body: some View {
        Form {
            // MARK: Vault / Folders
            Section {
                HStack {
                    Label("Vault Folder", systemImage: "folder.fill")
                    Spacer()
                    Text(vaultFolderName)
                        .font(.callout)
                        .foregroundStyle(vaultFolderName == "Not set" ? .orange : .secondary)
                }

                Button {
                    showFolderPicker = true
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }

                if appState.isLoadingItems {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Loading items…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("\(appState.items.count) items loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Vault")
            } footer: {
                Text("Place your Obsidian vault or markdown folder at Documents/ListAppVault, or choose a folder. iCloud Drive integration coming soon.")
            }

            // MARK: List Types (tappable)
            Section("List Types") {
                ForEach(appState.listTypes, id: \.name) { listType in
                    NavigationLink(destination: ListTypeDetailView(listType: listType)) {
                        HStack {
                            Image(systemName: iconForType(listType.name))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            Text(listType.name.capitalized)
                            Spacer()
                            let count = appState.items.filter { $0.type == listType.name }.count
                            Text("\(count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: Appearance
            Section("Appearance") {
                Picker("Theme", selection: $selectedTheme) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }
                Picker("Default Display", selection: $defaultDisplayStyle) {
                    Label("List", systemImage: "list.bullet").tag(DisplayStyle.list)
                    Label("Card", systemImage: "square.grid.2x2").tag(DisplayStyle.card)
                }
            }

            // MARK: About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Core.version).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Saved Views")
                    Spacer()
                    Text("\(appState.savedViews.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Tags")
                    Spacer()
                    Text("\(appState.allTags.count)").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(vaultFolderName: $vaultFolderName)
                .environment(appState)
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "movie": return "film"
        case "book": return "book.closed"
        case "todo": return "checkmark.circle"
        default: return "doc.text"
        }
    }
}

// MARK: - Simple Folder Picker Sheet

struct FolderPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var vaultFolderName: String

    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    /// List sub-folders of Documents (user can pick one as vault root)
    private var subFolders: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: docs.path))
            .map { $0.filter { entry in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: docs.appendingPathComponent(entry).path, isDirectory: &isDir)
                return isDir.boolValue
            }} ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Standard vault location
                    Button {
                        setVault(name: "ListAppVault")
                    } label: {
                        HStack {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            VStack(alignment: .leading) {
                                Text("ListAppVault (recommended)")
                                    .foregroundStyle(.primary)
                                Text("Documents/ListAppVault")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vaultFolderName == "ListAppVault" {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                } header: {
                    Text("Recommended")
                }

                if !subFolders.isEmpty {
                    Section("Folders in Documents") {
                        ForEach(subFolders, id: \.self) { folder in
                            Button {
                                setVault(name: folder)
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                                    Text(folder).foregroundStyle(.primary)
                                    Spacer()
                                    if vaultFolderName == folder {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("Place your markdown files in the chosen folder inside the Documents app. The app will scan it for todos, books, movies, and other items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choose Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func setVault(name: String) {
        let vaultURL = docs.appendingPathComponent(name)
        // Create folder if it doesn't exist
        try? FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        vaultFolderName = name
        // Trigger reload
        Task {
            await appState.reloadItems(from: vaultURL)
        }
        dismiss()
    }
}
