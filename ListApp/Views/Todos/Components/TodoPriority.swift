import SwiftUI
import Core

// Todoist-style 1–4 priority used in the design.
// Stored in Item.properties["priority"] as "p1"/"p2"/"p3"/"p4"
// (aliases for backwards-compat with existing high/medium/low).
enum TodoPriority: Int, CaseIterable, Identifiable {
    case p1 = 1, p2 = 2, p3 = 3, p4 = 4
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .p1: return "Priority 1"
        case .p2: return "Priority 2"
        case .p3: return "Priority 3"
        case .p4: return "Priority 4"
        }
    }

    var color: Color {
        switch self {
        case .p1: return TodoToken.red
        case .p2: return TodoToken.orange
        case .p3: return TodoToken.blue
        case .p4: return TodoToken.dim
        }
    }

    var storageValue: String { "p\(rawValue)" }

    static func from(_ value: PropertyValue?) -> TodoPriority? {
        guard case .text(let s) = value else { return nil }
        switch s.lowercased() {
        case "p1", "high":       return .p1
        case "p2", "medium":     return .p2
        case "p3":               return .p3
        case "p4", "low":        return .p4
        default: return nil
        }
    }
}

struct PriorityFlagView: View {
    let priority: TodoPriority
    var size: CGFloat = 14
    var body: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(priority.color)
            .accessibilityLabel(priority.label)
    }
}
