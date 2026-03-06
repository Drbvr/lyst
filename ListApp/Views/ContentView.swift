import SwiftUI
import Core

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
