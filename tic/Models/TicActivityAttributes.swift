import ActivityKit
import Foundation

struct TicActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var startDate: Date
        var endDate: Date
        var isReminder: Bool
        var calendarColorHex: String
    }
    var eventIdentifier: String
}
