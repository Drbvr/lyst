import SwiftUI
import Core

struct CitationChip: View {
    let ref: NoteRef
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var matchingItem: Item? {
        appState.items.first { $0.sourceFile == ref.file }
    }

    var body: some View {
        if let item = matchingItem {
            NavigationLink(value: item) {
                chipLabel(item.title)
            }
            .buttonStyle(.plain)
        } else {
            chipLabel(ref.displayName)
        }
    }

    private func chipLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption2)
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}
