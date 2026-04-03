import ActivityKit
import SwiftUI

@Observable
class LiveActivityService {
    private var currentActivity: Activity<TicActivityAttributes>?

    var isActivityActive: Bool { currentActivity != nil }

    func start(for item: TicItem) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = TicActivityAttributes(eventIdentifier: item.id)
        let state = TicActivityAttributes.ContentState(
            title: item.title,
            startDate: item.startDate ?? Date(),
            endDate: item.endDate ?? Date(),
            isReminder: item.isReminder,
            calendarColorHex: item.calendarColor.hexString
        )
        let content = ActivityContent(state: state, staleDate: item.endDate)
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        currentActivity = activity
    }

    func update(for item: TicItem) {
        guard let activity = currentActivity else { return }
        let state = TicActivityAttributes.ContentState(
            title: item.title,
            startDate: item.startDate ?? Date(),
            endDate: item.endDate ?? Date(),
            isReminder: item.isReminder,
            calendarColorHex: item.calendarColor.hexString
        )
        let content = ActivityContent(state: state, staleDate: item.endDate)
        Task {
            await activity.update(content)
        }
    }

    func end(for identifier: String) {
        guard let activity = currentActivity,
              activity.attributes.eventIdentifier == identifier else { return }
        let state = activity.content.state
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    func endAll() {
        Task {
            for activity in Activity<TicActivityAttributes>.activities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
    }

    func transition(to next: TicItem) throws {
        if let current = currentActivity {
            let state = current.content.state
            let content = ActivityContent(state: state, staleDate: nil)
            Task {
                await current.end(content, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
        try start(for: next)
    }
}

// MARK: - CGColor → Hex

extension CGColor {
    var hexString: String {
        guard let components = converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else {
            return "#FF6B35"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
