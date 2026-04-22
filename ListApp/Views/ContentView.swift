import SwiftUI
import Core

// MARK: - Platform Compatibility Helpers

extension View {
    @ViewBuilder
    func navigationBarTitleInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            TodosHomeView()
                .tabItem {
                    Label("Todos", systemImage: "checkmark.circle")
                }
                .tag(1)

            NotesBrowserView()
                .tabItem {
                    Label("Notes", systemImage: "square.stack")
                }
                .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(3)
        }
    }
}
