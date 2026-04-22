import SwiftUI

// Inset card that groups todo rows, matching the wireframe `Group` primitive.
struct TodoGroupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(TodoToken.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(TodoToken.lineS, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }
}

struct TodoSectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.3)
                .foregroundStyle(TodoToken.mute)
            Spacer()
            if let t = trailing {
                Text(t)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TodoToken.mute)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

struct TodoRowDivider: View {
    var body: some View {
        Rectangle().fill(TodoToken.lineS).frame(height: 0.5)
    }
}
