import SwiftUI
import Core

/// Bottom-sheet filter surface for the Notes tab.
///
/// Holds a draft copy of the filter state; only `Apply` commits the draft to
/// the caller. Drag-to-dismiss discards the draft (standard iOS convention).
struct NotesFilterSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let initialFilter: NotesFilterState
    let savedViewID: SavedView.ID?
    let onApply: (NotesFilterState) -> Void

    @State private var draft: NotesFilterState
    @State private var showCustomRange: Bool = false
    @State private var customStart: Date = Date()
    @State private var customEnd: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    init(
        initialFilter: NotesFilterState,
        savedViewID: SavedView.ID? = nil,
        onApply: @escaping (NotesFilterState) -> Void
    ) {
        self.initialFilter = initialFilter
        self.savedViewID = savedViewID
        self.onApply = onApply
        _draft = State(initialValue: initialFilter)
        if case .custom(let s, let e) = initialFilter.due {
            _customStart = State(initialValue: s)
            _customEnd   = State(initialValue: e)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    typeSection
                    statusSection
                    if !tagEntries.isEmpty {
                        tagsSection
                    }
                    dueSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 120)
            }

            applyFooter
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCustomRange) {
            customDateRangeSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Filters")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
            Spacer()
            Button("Reset") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    draft = .init()
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    // MARK: - Sections

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TYPE")
            FlowLayout(spacing: 8) {
                SheetChip(
                    icon: "square.grid.2x2",
                    label: "All",
                    isSelected: draft.type == nil
                ) {
                    draft.type = nil
                }
                ForEach(appState.itemTypeNames, id: \.self) { type in
                    SheetChip(
                        icon: iconForType(type),
                        label: type.capitalized,
                        isSelected: draft.type == type
                    ) {
                        draft.type = draft.type == type ? nil : type
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("STATUS")
            Picker("Status", selection: $draft.status) {
                Text("All").tag(NotesFilterState.Status.all)
                Text("Open").tag(NotesFilterState.Status.open)
                Text("Done").tag(NotesFilterState.Status.done)
            }
            .pickerStyle(.segmented)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TAGS")
            FlowLayout(spacing: 8) {
                ForEach(tagEntries, id: \.tag) { entry in
                    SheetChip(
                        icon: nil,
                        label: "#\(entry.tag)",
                        isSelected: draft.tags.contains(entry.tag)
                    ) {
                        toggleTag(entry.tag)
                    }
                }
            }
        }
    }

    private var dueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DUE")
            FlowLayout(spacing: 8) {
                dueChip("Any",        isSelected: draft.due == .any)       { draft.due = .any }
                dueChip("Today",      isSelected: draft.due == .today)     { draft.due = .today }
                dueChip("This week",  isSelected: draft.due == .thisWeek)  { draft.due = .thisWeek }
                dueChip("Overdue",    isSelected: draft.due == .overdue)   { draft.due = .overdue }
                dueChip(customChipLabel, isSelected: isCustomDue)          { showCustomRange = true }
            }
        }
    }

    private var customChipLabel: String {
        if case .custom(let s, let e) = draft.due {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "\(f.string(from: s))–\(f.string(from: e))"
        }
        return "Custom…"
    }

    private var isCustomDue: Bool {
        if case .custom = draft.due { return true }
        return false
    }

    @ViewBuilder
    private func dueChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        SheetChip(icon: nil, label: label, isSelected: isSelected, action: action)
    }

    // MARK: - Apply footer

    private var applyFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            Button {
                onApply(draft)
                dismiss()
            } label: {
                Text("Show \(draftMatchCount) results")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Custom range sheet

    private var customDateRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $customStart, displayedComponents: .date)
                DatePicker("End", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }
            .navigationTitle("Custom range")
            .navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCustomRange = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        draft.due = .custom(start: customStart, end: customEnd)
                        showCustomRange = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Derived data

    /// Items considered when counting matches and ranking tag chips. If the
    /// caller had a Saved View selected, scope to that view's items so the
    /// chips and preview count reflect work-in-context.
    private var baselineItems: [Item] {
        if let id = savedViewID,
           let sv = appState.savedViews.first(where: { $0.id == id }) {
            return appState.filteredItems(for: sv)
        }
        return appState.items
    }

    private var tagEntries: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in baselineItems {
            for tag in Set(item.tags) where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.tag < $1.tag : $0.count > $1.count }
    }

    private var draftMatchCount: Int {
        NotesFilterEvaluator.apply(draft, to: baselineItems).count
    }

    private func toggleTag(_ tag: String) {
        if draft.tags.contains(tag) {
            draft.tags.remove(tag)
            let prefix = tag + "/"
            for other in Array(draft.tags) where other.hasPrefix(prefix) {
                draft.tags.remove(other)
            }
        } else {
            draft.tags.insert(tag)
            let prefix = tag + "/"
            for entry in tagEntries where entry.tag.hasPrefix(prefix) {
                draft.tags.insert(entry.tag)
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    private func iconForType(_ typeName: String) -> String {
        switch typeName.lowercased() {
        case "todo":       return "checkmark.circle"
        case "book":       return "book"
        case "movie":      return "film"
        case "restaurant": return "fork.knife"
        default:           return "doc.text"
        }
    }
}

// MARK: - Sheet chip

private struct SheetChip: View {
    let icon: String?
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.primary : Color(.secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
