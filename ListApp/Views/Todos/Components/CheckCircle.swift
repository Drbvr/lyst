import SwiftUI
import Core

struct CheckCircle: View {
    let completed: Bool
    var size: CGFloat = 22
    var color: Color = TodoToken.mute
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(completed ? Color.clear : color, lineWidth: 1.5)
                    .background(
                        Circle().fill(completed ? TodoToken.green : Color.clear)
                    )
                    .frame(width: size, height: size)
                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(completed ? "Mark not done" : "Mark done")
    }
}
