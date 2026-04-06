import WidgetKit
import SwiftUI
import ActivityKit

struct TicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TicActivityAttributes.self) { context in
            let event = currentEvent(from: context.state)
            LockScreenView(event: event)
                .activityBackgroundTint(.black.opacity(0.85))
                .widgetURL(deepLinkURL(for: event.startDate))
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded
                DynamicIslandExpandedRegion(.leading) {
                    let ev = currentEvent(from: context.state)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("tic")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.orange)
                        Text(ev.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    let ev = currentEvent(from: context.state)
                    Text(timerInterval: ev.startDate...ev.endDate, countsDown: true)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    let ev = currentEvent(from: context.state)
                    VStack(spacing: 1) {
                        SimpleProgressBar(
                            progress: progressValue(start: ev.startDate, end: ev.endDate)
                        )
                        HStack {
                            Text(formatTime(ev.startDate))
                                .font(.system(size: 8, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer()
                            Text(formatTime(ev.endDate))
                                .font(.system(size: 8, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } compactLeading: {
                let ev = currentEvent(from: context.state)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                    Text(ev.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
            } compactTrailing: {
                let ev = currentEvent(from: context.state)
                Text(timerInterval: ev.startDate...ev.endDate, countsDown: true)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentTransition(.numericText(countsDown: true))
            } minimal: {
                let ev = currentEvent(from: context.state)
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progressValue(start: ev.startDate, end: ev.endDate))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - Helper: extract current event from state

private func currentEvent(from state: TicActivityAttributes.ContentState) -> ActivityEvent {
    if let idx = state.currentIndex, idx < state.events.count {
        return state.events[idx]
    }
    if let idx = state.nextIndex, idx < state.events.count {
        return state.events[idx]
    }
    return state.events.first ?? ActivityEvent(title: "", startDate: Date(), endDate: Date(), colorHex: "#FF6B35")
}

// MARK: - Simple Progress Bar

struct SimpleProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(Color.orange)
                    .frame(width: max(geo.size.width * progress, 4))
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let event: ActivityEvent

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("tic")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.orange)
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                }
                Spacer()
                Text(timerInterval: event.startDate...event.endDate, countsDown: true)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }

            SimpleProgressBar(
                progress: progressValue(start: event.startDate, end: event.endDate)
            )

            HStack {
                Text(formatTime(event.startDate))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(formatTime(event.endDate))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(16)
    }
}

// MARK: - Helpers

private func progressValue(start: Date, end: Date) -> CGFloat {
    let now = Date()
    let total = end.timeIntervalSince(start)
    guard total > 0 else { return 0 }
    let elapsed = now.timeIntervalSince(start)
    return min(max(CGFloat(elapsed / total), 0), 1)
}

private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func deepLinkURL(for date: Date) -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return URL(string: "tic://day?date=\(formatter.string(from: date))")!
}
