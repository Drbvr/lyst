import Foundation
import Core

// Shared filtering/grouping helpers for the Todos tab.
// All data remains in md files — these helpers only read AppState.items.
enum TodoQueries {

    static func isTodo(_ item: Item) -> Bool { item.type == "todo" }

    static func dueDate(_ item: Item) -> Date? {
        if case .date(let d) = item.properties["dueDate"] { return d }
        if case .date(let d) = item.properties["deadline"] { return d }
        return nil
    }

    static func openTodos(_ items: [Item]) -> [Item] {
        items.filter { isTodo($0) && !$0.completed }
    }

    static func overdueCount(_ items: [Item], now: Date = Date()) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        return openTodos(items).filter { (dueDate($0) ?? .distantFuture) < start }.count
    }

    static func forToday(_ items: [Item], now: Date = Date()) -> (overdue: [Item], today: [Item], noDate: [Item]) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end   = cal.date(byAdding: .day, value: 1, to: start) ?? now
        var overdue: [Item] = [], today: [Item] = [], noDate: [Item] = []
        for it in openTodos(items) {
            if let d = dueDate(it) {
                if d < start { overdue.append(it) }
                else if d < end { today.append(it) }
            } else {
                noDate.append(it)
            }
        }
        func sortByPriority(_ a: [Item]) -> [Item] {
            a.sorted { (TodoPriorityRank.from($0)) < (TodoPriorityRank.from($1)) }
        }
        return (sortByPriority(overdue), sortByPriority(today), sortByPriority(noDate))
    }

    static func forWeek(_ items: [Item], startOfWeek: Date) -> [[Item]] {
        let cal = Calendar.current
        var out = Array(repeating: [Item](), count: 7)
        for it in openTodos(items) {
            guard let d = dueDate(it) else { continue }
            let diff = cal.dateComponents([.day], from: cal.startOfDay(for: startOfWeek),
                                          to: cal.startOfDay(for: d)).day ?? -1
            if (0..<7).contains(diff) { out[diff].append(it) }
        }
        return out.map { bucket in
            bucket.sorted { (dueDate($0) ?? .distantFuture) < (dueDate($1) ?? .distantFuture) }
        }
    }

    static func inbox(_ items: [Item]) -> [Item] {
        openTodos(items).filter { $0.sourceFile.hasSuffix("/Inbox.md") }
    }

    static func completed(_ items: [Item]) -> [Item] {
        items.filter { isTodo($0) && $0.completed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Top-level tag = "project" (first segment before `/`).
    static func projects(_ items: [Item]) -> [(name: String, open: Int)] {
        var counts: [String: Int] = [:]
        for it in openTodos(items) {
            for tag in it.tags {
                let top = tag.split(separator: "/").first.map(String.init) ?? tag
                counts[top, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    /// Top-level labels (all leaf tags) with counts.
    static func labels(_ items: [Item]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for it in openTodos(items) {
            for tag in it.tags where !tag.contains("/") {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    static func inProject(_ items: [Item], project: String) -> [Item] {
        openTodos(items).filter { item in
            item.tags.contains { $0 == project || $0.hasPrefix("\(project)/") }
        }
    }
}

enum TodoPriorityRank {
    static func from(_ item: Item) -> Int {
        if let p = TodoPriority.from(item.properties["priority"]) { return p.rawValue }
        return 5
    }
}
