import SwiftUI
import Core

/// Inline editable review card for a `DraftBundle` attached to an assistant
/// message. Paginates via TabView when the bundle has more than one draft.
///
/// The card hands callbacks back to `ChatViewModel` rather than mutating the
/// message directly, so the view model remains the single source of truth for
/// message state and the UI stays stateless modulo per-card scratch state.
struct DraftCard: View {
    let bundle: DraftBundle
    let onUpdate: (_ draftId: UUID, _ mutate: (inout NoteEdit) -> Void) -> Void
    let onToggleIncluded: (_ draftId: UUID) -> Void
    let onRegenerate: (_ feedback: String) -> Void
    let onSave: () -> Void

    @State private var selectedIndex: Int = 0
    @State private var feedback: String = ""

    private var includedCount: Int {
        bundle.drafts.filter(\.isIncluded).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if bundle.drafts.count > 1 {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(bundle.drafts.enumerated()), id: \.element.id) { index, draft in
                        draftEditor(draft)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(minHeight: 280)
            } else if let only = bundle.drafts.first {
                draftEditor(only)
            }
            if !bundle.isSaved {
                footer
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .disabled(bundle.isSaved)
        .opacity(bundle.isSaved ? 0.6 : 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .foregroundStyle(Color.accentColor)
            Text(bundle.drafts.count == 1 ? "Proposed note" : "Proposed notes (\(bundle.drafts.count))")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if bundle.isSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    // MARK: - Per-draft editor

    @ViewBuilder
    private func draftEditor(_ draft: NoteEdit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("type", text: binding(for: draft, keyPath: \.type))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 160)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Title", text: binding(for: draft, keyPath: \.title))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tags (comma-separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. work, project/alpha", text: binding(for: draft, keyPath: \.tags))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            if !draft.properties.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Properties")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(draft.properties.keys.sorted(), id: \.self) { key in
                        propertyRow(draft: draft, key: key)
                    }
                }
            }

            Toggle(isOn: includedBinding(for: draft)) {
                Text("Include this draft")
                    .font(.caption)
            }
            .tint(.accentColor)
        }
    }

    @ViewBuilder
    private func propertyRow(draft: NoteEdit, key: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(key)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            TextField(key, text: propertyBinding(draftId: draft.id, key: key, current: draft.properties[key]))
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Footer (feedback + actions)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            TextField("Feedback for revision (optional)", text: $feedback, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button {
                    let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onRegenerate(trimmed)
                    feedback = ""
                } label: {
                    Text("Regenerate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    onSave()
                } label: {
                    Text(saveButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(includedCount == 0)
            }
        }
    }

    private var saveButtonTitle: String {
        switch includedCount {
        case 0:  return "Save"
        case 1:  return "Save note"
        default: return "Save \(includedCount) notes"
        }
    }

    // MARK: - Bindings

    private func binding(for draft: NoteEdit, keyPath: WritableKeyPath<NoteEdit, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                onUpdate(draft.id) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func includedBinding(for draft: NoteEdit) -> Binding<Bool> {
        Binding(
            get: { draft.isIncluded },
            set: { _ in onToggleIncluded(draft.id) }
        )
    }

    private func propertyBinding(draftId: UUID, key: String, current: PropertyValue?) -> Binding<String> {
        Binding(
            get: {
                guard let current else { return "" }
                return Self.propertyString(current)
            },
            set: { newValue in
                onUpdate(draftId) { $0.properties[key] = .text(newValue) }
            }
        )
    }

    private static func propertyString(_ value: PropertyValue) -> String {
        switch value {
        case .text(let s):   return s
        case .number(let n):
            if n.truncatingRemainder(dividingBy: 1) == 0 {
                return String(Int(n))
            }
            return String(n)
        case .bool(let b):   return b ? "true" : "false"
        case .date(let d):
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            return f.string(from: d)
        }
    }
}
