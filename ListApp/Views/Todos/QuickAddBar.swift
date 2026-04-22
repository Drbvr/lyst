import SwiftUI
import Core

struct QuickAddBar: View {
    var onSubmit: (String) -> Void
    @State private var text: String = ""
    @State private var preview: QuickAddResult = .init()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 18, weight: .light))
                    .foregroundStyle(TodoToken.blue)
                TextField("Add a todo — try \"demo fri 10am p1 #work\"", text: $text)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .foregroundStyle(TodoToken.fg)
                    .onChange(of: text) { _, new in
                        preview = QuickAddParser.parse(new)
                    }
                    .onSubmit { submit() }
                if !text.isEmpty {
                    Button("Save") { submit() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TodoToken.blue)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TodoToken.line,
                                                                     style: StrokeStyle(lineWidth: 1, dash: [4,3])))

            if !text.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let d = preview.dueDate {
                            previewChip(text: formatted(d), icon: "calendar")
                        }
                        if let p = preview.priority {
                            previewChip(text: p.uppercased(), icon: "flag.fill")
                        }
                        if let pr = preview.project {
                            previewChip(text: "#\(pr)", icon: "number")
                        }
                        ForEach(preview.labels, id: \.self) { l in
                            previewChip(text: "@\(l)", icon: "tag")
                        }
                        if let r = preview.recurrence {
                            previewChip(text: r, icon: "arrow.triangle.2.circlepath")
                        }
                    }.padding(.horizontal, 4)
                }
            }
        }
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSubmit(text); text = ""; preview = .init()
    }

    private func previewChip(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(TodoToken.blue)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(TodoToken.blue.opacity(0.14)))
    }

    private func formatted(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E d MMM, HH:mm"
        return f.string(from: d)
    }
}
