import SwiftUI

@main
struct ListAppApp: App {
    @State private var appState = AppState()

    private var preferredColorScheme: ColorScheme? {
        switch appState.selectedTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .preferredColorScheme(preferredColorScheme)
                .onOpenURL { url in
                    if url.scheme == "lijster" {
                        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                              let webURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                              let webURL = URL(string: webURLString) else { return }
                        appState.pendingImport = .webURL(webURL)
                    } else if url.isFileURL {
                        appState.pendingImport = .image(url)
                    } else if url.scheme == "https" || url.scheme == "http" {
                        appState.pendingImport = .webURL(url)
                    }
                }
                .sheet(item: Bindable(appState).pendingImport) { pending in
                    ImportView(pending: pending)
                        .environment(appState)
                }
        }
    }
}
