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
                    // External share / URL scheme: queue as a chat attachment.
                    // ChatView picks up `appState.pendingImport` and converts it
                    // into `ChatAttachment`s on the composer.
                    if url.scheme == "lijster" {
                        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                              let webURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                              let webURL = URL(string: webURLString) else { return }
                        appState.pendingImport = PendingImport(webURL: webURL)
                    } else if url.isFileURL {
                        appState.pendingImport = PendingImport(image: url)
                    } else if url.scheme == "https" || url.scheme == "http" {
                        appState.pendingImport = PendingImport(webURL: url)
                    }
                }
        }
    }
}
