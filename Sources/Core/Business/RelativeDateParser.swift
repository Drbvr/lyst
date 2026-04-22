import Foundation

/// Parses relative date strings like "+7d", "-30d", "+2w", "-1m", "+1y"
public struct RelativeDateParser {

    public init() {}

    /// Parses a relative date string and returns an absolute Date
    /// Supported formats:
    /// - "+7d" or "-7d" (days)
    /// - "+2w" or "-2w" (weeks)
    /// - "+1m" or "-1m" (months)
    /// - "+1y" or "-1y" (years)
    public func parse(_ input: String) -> Date? {
        guard !input.isEmpty else { return nil }

        // Extract sign, number, and unit
        let firstChar = input.first
        guard firstChar == "+" || firstChar == "-" else { return nil }

        let sign = firstChar == "+" ? 1 : -1

        // Extract number and unit
        let remaining = String(input.dropFirst())
        var numberString = ""
        var unitString = ""

        for char in remaining {
            if char.isNumber {
                numberString.append(char)
            } else {
                unitString.append(char)
            }
        }

        guard !numberString.isEmpty, !unitString.isEmpty else { return nil }

        guard let number = Int(numberString), number >= 0 else { return nil }

        let calendar = Calendar.current
        let now = Date()

        switch unitString {
        case "d":
            // Days
            var components = DateComponents()
            components.day = sign * number
            return calendar.date(byAdding: components, to: now)

        case "w":
            // Weeks
            var components = DateComponents()
            components.weekOfYear = sign * number
            return calendar.date(byAdding: components, to: now)

        case "m":
            // Months
            var components = DateComponents()
            components.month = sign * number
            return calendar.date(byAdding: components, to: now)

        case "y":
            // Years
            var components = DateComponents()
            components.year = sign * number
            return calendar.date(byAdding: components, to: now)

        default:
            return nil
        }
    }
}
