import Foundation

enum TodoScope: String, Hashable, CaseIterable, Identifiable {
    case today, upcoming, inbox, projects, labels
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .inbox: return "Inbox"
        case .projects: return "Projects"
        case .labels: return "Labels"
        }
    }
}
