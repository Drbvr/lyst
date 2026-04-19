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
    @State private var showCreate: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SavedViewsListView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(0)

            NavigationStack {
                FilterView()
            }
            .tabItem {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .tag(1)

            // Centre "+" tab — intercepted to open a sheet
            Color.clear
                .tabItem {
                    Label("New", systemImage: "plus.circle.fill")
                }
                .tag(2)

            NavigationStack {
                TagBrowserView()
            }
            .tabItem {
                Label("Tags", systemImage: "tag")
            }
            .tag(3)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(4)

            ChatView()
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(5)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(6)
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 2 {
                showCreate = true
                selectedTab = 0   // jump back to previous tab
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateItemView()
                .environment(appState)
        }
    }
}
