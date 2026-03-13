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

    var body: some View {
        TabView {
            NavigationStack {
                SavedViewsListView()
            }
            .tabItem {
                Label("Views", systemImage: "list.bullet.rectangle")
            }

            NavigationStack {
                FilterView()
            }
            .tabItem {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }

            NavigationStack {
                TagBrowserView()
            }
            .tabItem {
                Label("Tags", systemImage: "tag")
            }

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
    }
}
