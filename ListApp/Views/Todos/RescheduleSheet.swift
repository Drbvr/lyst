import SwiftUI
import Core

struct RescheduleSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let item: Item
    @State private var date: Date = Date()

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        chip("Today")      { set(cal.startOfDay(for: .now)) }
                        chip("Tomorrow")   { set(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!) }
                        chip("Weekend")    { set(nextWeekend()) }
                        chip("Next week")  { set(cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: .now))!) }
                        chip("Someday")    { apply(nil) }
                    }
                    .padding(.horizontal, 16)

                    DatePicker("Date & time", selection: $date)
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, 16)

                    Button {
                        apply(date)
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
            .navigationTitle("Reschedule").navigationBarTitleInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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

    private func set(_ d: Date) { date = d }

    private func nextWeekend() -> Date {
        var d = cal.startOfDay(for: .now)
        while cal.component(.weekday, from: d) != 7 { // Saturday
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    private func apply(_ d: Date?) {
        var updated = item
        if let d = d { updated.properties["dueDate"] = .date(d) }
        else { updated.properties.removeValue(forKey: "dueDate") }
        appState.updateItem(updated)
        dismiss()
    }
}
