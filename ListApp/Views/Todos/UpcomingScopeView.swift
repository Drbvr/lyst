import SwiftUI
import Core

struct UpcomingScopeView: View {
    @Environment(AppState.self) private var appState
    let items: [Item]
    @State private var selectedDay: Int = 0
    @State private var selection: Set<UUID> = []

    private var startOfWeek: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        let week = TodoQueries.forWeek(items, startOfWeek: startOfWeek)
        VStack(spacing: 0) {
            WeekStripView(
                startDate: startOfWeek,
                counts: week.map(\.count),
                selectedIndex: $selectedDay
            )
            .padding(.bottom, 14)

            ForEach(0..<7, id: \.self) { i in
                let day = Calendar.current.date(byAdding: .day, value: i, to: startOfWeek) ?? startOfWeek
                let bucket = week[i]
                if !bucket.isEmpty {
                    TodoSectionHeader(title: label(for: day, index: i), trailing: "\(bucket.count)")
                    TodoGroupCard {
                        ForEach(Array(bucket.enumerated()), id: \.element.id) { idx, item in
                            TodoRowSwipe(item: item, isBulkSelecting: false, selection: $selection)
                            if idx < bucket.count - 1 { TodoRowDivider() }
                        }
                    }
                }
            }
        }
    }

    private func label(for date: Date, index: Int) -> String {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        if index == 0 { return "Today · \(f.string(from: date))" }
        if cal.isDateInTomorrow(date) { return "Tomorrow · \(f.string(from: date))" }
        return f.string(from: date)
    }
}
