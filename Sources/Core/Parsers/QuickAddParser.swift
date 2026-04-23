import Foundation

/// Natural-language parser for the Todo quick-add field.
///
/// Parses a raw user string like:
///   "Plan offsite fri 10am p1 #work @urgent"
/// into a structured `QuickAddResult` that carries the cleaned title plus any
/// recognized date, priority, project, and label tokens — so the UI can preview
/// them as chips and `AppState.createTodo` can write them to markdown.
///
/// This is intentionally conservative: only patterns that are unambiguous are
/// extracted. Ambiguous inputs (e.g. "next") fall through to the title.
public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var dueDate: Date?
    public var priority: String?   // "p1".."p4"
    public var project: String?    // single top-level tag (first `#x`)
    public var labels: [String]    // `@label` tokens
    public var recurrence: String? // e.g. "every mon"
    public var reminder: String?   // e.g. "2h"

    public init(title: String = "", dueDate: Date? = nil, priority: String? = nil,
                project: String? = nil, labels: [String] = [],
                recurrence: String? = nil, reminder: String? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.project = project
        self.labels = labels
        self.recurrence = recurrence
        self.reminder = reminder
    }
}

public enum QuickAddParser {

    /// Parse `input` relative to `now`. Dates are returned in `calendar.timeZone`.
    public static func parse(_ input: String,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> QuickAddResult {
        var tokens = input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        var result = QuickAddResult()

        var keep: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let lower = t.lowercased()

            // Priority p1..p4
            if let rx = lower.range(of: #"^p[1-4]$"#, options: .regularExpression) {
                result.priority = String(lower[rx])
                i += 1; continue
            }
            // Project #tag
            if t.hasPrefix("#") && t.count > 1 {
                if result.project == nil {
                    result.project = String(t.dropFirst())
                } else {
                    // treat additional hashtags as labels-on-tag
                    result.labels.append(String(t.dropFirst()))
                }
                i += 1; continue
            }
            // Label @label
            if t.hasPrefix("@") && t.count > 1 {
                result.labels.append(String(t.dropFirst()))
                i += 1; continue
            }
            // Reminder ◷2h  or reminder:2h
            if lower.hasPrefix("◷") || lower.hasPrefix("reminder:") {
                let tail = lower.replacingOccurrences(of: "reminder:", with: "")
                    .replacingOccurrences(of: "◷", with: "")
                if !tail.isEmpty { result.reminder = tail }
                i += 1; continue
            }
            // Every <weekday>  → recurrence + derive first occurrence
            if lower == "every", i + 1 < tokens.count,
               let wd = weekdayIndex(tokens[i+1]) {
                result.recurrence = "every \(tokens[i+1].lowercased())"
                result.dueDate = nextWeekday(wd, from: now, calendar: calendar)
                i += 2; continue
            }
            // Weekdays (fri, friday, …) optionally followed by a time ("10am", "14:00")
            if let wd = weekdayIndex(t) {
                var date = nextWeekday(wd, from: now, calendar: calendar)
                if i + 1 < tokens.count, let time = parseTime(tokens[i+1]) {
                    date = apply(time: time, to: date, calendar: calendar)
                    i += 2
                } else {
                    i += 1
                }
                result.dueDate = date
                continue
            }
            // "today" / "tomorrow" / "tonight"
            if lower == "today" {
                result.dueDate = calendar.startOfDay(for: now)
                i += 1; continue
            }
            if lower == "tomorrow" || lower == "tmrw" {
                let start = calendar.startOfDay(for: now)
                result.dueDate = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
                i += 1; continue
            }
            if lower == "tonight" {
                var base = calendar.startOfDay(for: now)
                base = calendar.date(byAdding: .hour, value: 20, to: base) ?? base
                result.dueDate = base
                i += 1; continue
            }

            keep.append(t)
            i += 1
        }

        result.title = keep.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // MARK: - Internals

    /// Returns the Gregorian weekday (1=Sun … 7=Sat) matching `token`, or nil.
    static func weekdayIndex(_ token: String) -> Int? {
        let map: [String: Int] = [
            "sun": 1, "sunday": 1,
            "mon": 2, "monday": 2,
            "tue": 3, "tues": 3, "tuesday": 3,
            "wed": 4, "weds": 4, "wednesday": 4,
            "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
            "fri": 6, "friday": 6,
            "sat": 7, "saturday": 7,
        ]
        return map[token.lowercased()]
    }

    /// Next occurrence of `weekday` on-or-after `from` (exclusive of today if today
    /// matches — so "fri" on a Friday means the next Friday). Start-of-day time.
    static func nextWeekday(_ weekday: Int, from date: Date, calendar: Calendar) -> Date {
        let cur = calendar.component(.weekday, from: date)
        var add = weekday - cur
        if add <= 0 { add += 7 }
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: add, to: start) ?? start
    }

    struct ParsedTime { let hour: Int; let minute: Int }

    /// "10am", "10:30", "14:00", "9pm", … → (hour, minute) or nil.
    static func parseTime(_ token: String) -> ParsedTime? {
        let s = token.lowercased()
        if let r = s.range(of: #"^(\d{1,2}):(\d{2})$"#, options: .regularExpression) {
            let parts = String(s[r]).split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) {
                return ParsedTime(hour: parts[0], minute: parts[1])
            }
        }
        if let r = s.range(of: #"^(\d{1,2})(am|pm)$"#, options: .regularExpression) {
            let match = String(s[r])
            let isPM = match.hasSuffix("pm")
            let h = Int(match.dropLast(2)) ?? 0
            guard (1...12).contains(h) else { return nil }
            let hour24 = (h % 12) + (isPM ? 12 : 0)
            return ParsedTime(hour: hour24, minute: 0)
        }
        return nil
    }

    static func apply(time: ParsedTime, to date: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = time.hour
        comps.minute = time.minute
        return calendar.date(from: comps) ?? date
    }
}
