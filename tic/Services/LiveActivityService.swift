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

    /// 오늘의 전체 일정으로 Live Activity 시작
    func start(events: [TicItem]) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard canStart else { return }

        let filtered = filterAndSort(events)
        guard !filtered.isEmpty else { return }

        let activityEvents = toActivityEvents(filtered)
        let (currentIndex, nextIndex) = computeIndices(events: activityEvents)

        let attributes = TicActivityAttributes()
        let state = TicActivityAttributes.ContentState(
            events: activityEvents,
            currentIndex: currentIndex,
            nextIndex: nextIndex
        )
        let staleDate = activityEvents.map(\.endDate).max()
        let content = ActivityContent(state: state, staleDate: staleDate)
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        currentActivity = activity
    }

    /// 상태 갱신 (currentIndex/nextIndex 재계산)
    func update(events: [TicItem]) {
        guard let activity = currentActivity else { return }

        let filtered = filterAndSort(events)
        let activityEvents = toActivityEvents(filtered)
        let (currentIndex, nextIndex) = computeIndices(events: activityEvents)

        let state = TicActivityAttributes.ContentState(
            events: activityEvents,
            currentIndex: currentIndex,
            nextIndex: nextIndex
        )
        let staleDate = activityEvents.map(\.endDate).max()
        let content = ActivityContent(state: state, staleDate: staleDate)
        Task {
            await activity.update(content)
        }
    }

    /// 특정 activity 종료
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

    /// 모든 activity 종료
    func endAll() {
        Task {
            for activity in Activity<TicActivityAttributes>.activities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        lastEndTime = Date()
    }

    // MARK: - Private Helpers

    private func filterAndSort(_ events: [TicItem]) -> [TicItem] {
        events
            .filter { $0.startDate != nil && $0.endDate != nil && !$0.isAllDay }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .prefix(10)
            .map { $0 }
    }

    private func toActivityEvents(_ items: [TicItem]) -> [ActivityEvent] {
        let now = Date()
        return items.map { item in
            ActivityEvent(
                title: item.title,
                startDate: item.startDate ?? now,
                endDate: item.endDate ?? now,
                colorHex: item.calendarColor.hexString
            )
        }
    }

    private func computeIndices(events: [ActivityEvent]) -> (current: Int?, next: Int?) {
        let now = Date()
        var currentIdx: Int? = nil
        var nextIdx: Int? = nil

        for (i, event) in events.enumerated() {
            if event.startDate <= now && now < event.endDate {
                currentIdx = i
            }
            if event.startDate > now && nextIdx == nil {
                nextIdx = i
            }
        }

        // currentIndex가 있고 nextIdx가 없으면, current 다음 일정을 next로
        if let ci = currentIdx, nextIdx == nil, ci + 1 < events.count {
            nextIdx = ci + 1
        }

        return (currentIdx, nextIdx)
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
