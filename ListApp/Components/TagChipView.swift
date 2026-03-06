import SwiftUI

struct TagChipView: View {
    let tag: String

    var body: some View {
        Text("#\(tag)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())
    }
}
