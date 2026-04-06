import ActivityKit
import SwiftUI

@Observable
class LiveActivityService {
    private var currentActivity: Activity<TicActivityAttributes>?
    private var lastEndTime: Date?

    var isActivityActive: Bool { currentActivity != nil }

    // 종료 후 30초 내 재시작 방지
    var canStart: Bool {
        guard let lastEnd = lastEndTime else { return true }
        return Date().timeIntervalSince(lastEnd) > 30
    }

    func start(events: [TicItem]) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard canStart else { return }

        let now = Date()
        let activityEvents = events.prefix(10).map { item in
            ActivityEvent(
                title: item.title,
                startDate: item.startDate ?? now,
                endDate: item.endDate ?? now,
                colorHex: item.calendarColor.hexString
            )
        }

        // currentIndex/nextIndex 계산
        var currentIndex: Int?
        var nextIndex: Int?
        for (i, item) in events.prefix(10).enumerated() {
            guard let start = item.startDate, let end = item.endDate else { continue }
            if start <= now && end > now && currentIndex == nil {
                currentIndex = i
            } else if start > now && nextIndex == nil {
                nextIndex = i
            }
        }

        let attributes = TicActivityAttributes()
        let state = TicActivityAttributes.ContentState(
            events: activityEvents,
            currentIndex: currentIndex,
            nextIndex: nextIndex
        )
        let staleDate = events.compactMap(\.endDate).max()
        let content = ActivityContent(state: state, staleDate: staleDate)
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        currentActivity = activity
    }

    func update(events: [TicItem]) {
        guard let activity = currentActivity else { return }

        let now = Date()
        let activityEvents = events.prefix(10).map { item in
            ActivityEvent(
                title: item.title,
                startDate: item.startDate ?? now,
                endDate: item.endDate ?? now,
                colorHex: item.calendarColor.hexString
            )
        }

        var currentIndex: Int?
        var nextIndex: Int?
        for (i, item) in events.prefix(10).enumerated() {
            guard let start = item.startDate, let end = item.endDate else { continue }
            if start <= now && end > now && currentIndex == nil {
                currentIndex = i
            } else if start > now && nextIndex == nil {
                nextIndex = i
            }
        }

        let state = TicActivityAttributes.ContentState(
            events: activityEvents,
            currentIndex: currentIndex,
            nextIndex: nextIndex
        )
        let staleDate = events.compactMap(\.endDate).max()
        let content = ActivityContent(state: state, staleDate: staleDate)
        Task {
            await activity.update(content)
        }
    }

    func end(for identifier: String) {
        guard let activity = currentActivity else { return }
        let state = activity.content.state
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        lastEndTime = Date()
    }

    func endAll() {
        Task {
            for activity in Activity<TicActivityAttributes>.activities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        lastEndTime = Date()
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
