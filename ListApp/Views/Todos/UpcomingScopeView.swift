import SwiftUI
import Core

struct UpcomingScopeView: View {
    @Environment(AppState.self) private var appState
    let items: [Item]
    @State private var selectedDay: Int = 0
    @State private var selection: Set<UUID> = []

    private var startOfWeek: Date { Calendar.current.startOfDay(for: Date()) }
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    var body: some View {
        let week = TodoQueries.forWeek(items, startOfWeek: startOfWeek)
        VStack(spacing: 0) {
            WeekStripView(
                startDate: startOfWeek,
                counts: week.map(\.count),
                selectedIndex: $selectedDay
            )
            .padding(.bottom, 14)

            let day = Calendar.current.date(byAdding: .day, value: selectedDay, to: startOfWeek) ?? startOfWeek
            let bucket = week[selectedDay]
            if !bucket.isEmpty {
                TodoSectionHeader(title: label(for: day, index: selectedDay), trailing: "\(bucket.count)")
                TodoGroupCard {
                    ForEach(Array(bucket.enumerated()), id: \.element.id) { idx, item in
                        TodoRowSwipe(item: item, isBulkSelecting: false, selection: $selection)
                        if idx < bucket.count - 1 { TodoRowDivider() }
                    }
                }
            } else {
                Text("No todos scheduled for this day")
                    .foregroundStyle(TodoToken.mute)
                    .padding(20)
            }
        }
    }

    private func label(for date: Date, index: Int) -> String {
        let cal = Calendar.current
        if index == 0 { return "Today · \(dateFormatter.string(from: date))" }
        if cal.isDateInTomorrow(date) { return "Tomorrow · \(dateFormatter.string(from: date))" }
        return dateFormatter.string(from: date)
    }
}
