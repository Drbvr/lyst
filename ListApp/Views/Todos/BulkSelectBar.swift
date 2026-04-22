import SwiftUI
import Core

struct BulkSelectBar: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: Set<UUID>
    let allItems: [Item]
    let onDone: () -> Void
    @State private var showReschedule = false
    @State private var rescheduleTo: Date?

    private var selected: [Item] { allItems.filter { selection.contains($0.id) } }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(selection.count) selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            bulkButton("checkmark", "Done") {
                for it in selected { appState.toggleCompletion(for: it) }
                finish()
            }
            bulkButton("calendar", "Schedule") { showReschedule = true }
            bulkButton("tag", "Label") { /* would open label picker */ finish() }
            bulkButton("trash", "Delete") {
                for it in selected { appState.deleteItem(it) }
                finish()
            }
            Button { finish() } label: {
                Image(systemName: "xmark").foregroundStyle(.white).padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.14))
                .shadow(radius: 10, y: 4)
        )
        .padding(.horizontal, 16).padding(.bottom, 20)
        .sheet(isPresented: $showReschedule) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 8) {
                            chip("Today")      { rescheduleTo = Calendar.current.startOfDay(for: .now) }
                            chip("Tomorrow")   { rescheduleTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))! }
                            chip("Next week")  { rescheduleTo = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))! }
                            chip("Someday")    { rescheduleTo = nil }
                        }
                        .padding(.horizontal, 16)

                        DatePicker("Date & time", selection: Binding(
                            get: { rescheduleTo ?? .now },
                            set: { rescheduleTo = $0 }
                        ))
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, 16)

                        Button {
                            for item in selected {
                                var updated = item
                                if let date = rescheduleTo {
                                    updated.properties["dueDate"] = .date(date)
                                } else {
                                    updated.properties.removeValue(forKey: "dueDate")
                                }
                                appState.updateItem(updated)
                            }
                            showReschedule = false
                            finish()
                        } label: {
                            Text("Schedule")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(RoundedRectangle(cornerRadius: 12).fill(TodoToken.blue))
                        }.buttonStyle(.plain).padding(.horizontal, 16)
                    }.padding(.vertical, 16)
                }
                .navigationTitle("Reschedule \(selected.count) todos").navigationBarTitleInline()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showReschedule = false } }
                }
            }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(TodoToken.fillS))
                .foregroundStyle(TodoToken.fg)
        }.buttonStyle(.plain)
    }

    private func bulkButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 16))
                Text(label).font(.system(size: 10))
            }.foregroundStyle(.white)
        }.buttonStyle(.plain)
    }

    private func finish() { selection = []; onDone() }
}
