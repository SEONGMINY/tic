import SwiftData
import Foundation

@Model
class CalendarSelection {
    @Attribute(.unique) var calendarIdentifier: String
    var isEnabled: Bool

    init(calendarIdentifier: String, isEnabled: Bool = true) {
        self.calendarIdentifier = calendarIdentifier
        self.isEnabled = isEnabled
    }
}
