import SwiftUI

struct SegmentedScopePicker<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { (tag, label) in
                    let selected = tag == selection
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selection = tag }
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? Color.black : TodoToken.fg)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selected ? TodoToken.fg : Color.clear)
                            )
                            .overlay(
                                Capsule().strokeBorder(selected ? Color.clear : TodoToken.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
