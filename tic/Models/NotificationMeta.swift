import SwiftData
import Foundation

@Model
class NotificationMeta {
    @Attribute(.unique) var eventIdentifier: String
    var snoozedUntil: Date?

    init(eventIdentifier: String) {
        self.eventIdentifier = eventIdentifier
    }
}
