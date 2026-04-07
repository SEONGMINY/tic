import WidgetKit
import SwiftUI
import ActivityKit

struct TicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TicActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.85))
                .widgetURL(deepLinkURL(for: context.state.events))
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Text("tic")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        ProgressLineView(events: context.state.events, currentIndex: context.state.currentIndex)
                        if let first = context.state.events.first, let last = context.state.events.last {
                            HStack {
                                Text(formatTime(first.startDate))
                                    .font(.system(size: 8, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Spacer()
                                Text(formatTime(last.endDate))
                                    .font(.system(size: 8, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text(currentOrNextTitle(state: context.state))
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            } compactTrailing: {
                compactCountdownView(state: context.state)
            } minimal: {
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: overallProgress(events: context.state.events))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let state: TicActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            // 상단: tic 로고 + 카운트다운
            HStack(alignment: .top) {
                Text("tic")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.orange)
                Spacer()
                countdownView(state: state)
            }

            // Progress line + 시간 라벨
            if !state.events.isEmpty {
                VStack(spacing: 2) {
                    ProgressLineView(events: state.events, currentIndex: state.currentIndex)
                    if let first = state.events.first, let last = state.events.last {
                        HStack {
                            Text(formatTime(first.startDate))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Spacer()
                            Text(formatTime(last.endDate))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            // 지금/다음 라벨
            VStack(spacing: 4) {
                if let ci = state.currentIndex, ci < state.events.count {
                    let event = state.events[ci]
                    HStack {
                        Text("지금")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                        Text(event.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text(timeRange(event))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if let ni = state.nextIndex, ni < state.events.count {
                    let event = state.events[ni]
                    HStack {
                        Text("다음")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(event.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text(timeRange(event))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Progress Line View

private struct ProgressLineView: View {
    let events: [ActivityEvent]
    let currentIndex: Int?

    private var totalTimeRange: (start: Date, end: Date, duration: TimeInterval) {
        guard let first = events.first, let last = events.last else {
            let now = Date()
            return (now, now, 0)
        }
        let start = first.startDate
        let end = last.endDate
        return (start, end, end.timeIntervalSince(start))
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let range = totalTimeRange
            let now = Date()
            let progress: CGFloat = range.duration > 0
                ? min(max(CGFloat(now.timeIntervalSince(range.start) / range.duration), 0), 1)
                : 0
            let progressX = totalWidth * progress

            ZStack(alignment: .leading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 10))
                    path.addLine(to: CGPoint(x: totalWidth, y: 10))
                }
                .stroke(
                    Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6])
                )

                if progressX > 0 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 10))
                        path.addLine(to: CGPoint(x: progressX, y: 10))
                    }
                    .stroke(
                        Color.orange,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }

                ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                    let x = xPosition(for: event.startDate, in: range, totalWidth: totalWidth)
                    ProgressEventDot(
                        state: dotState(for: event, index: index, now: now),
                        currentProgress: eventProgress(for: event, now: now)
                    )
                    .position(x: max(min(x, totalWidth - 10), 10), y: 10)
                }
            }
        }
        .frame(height: 22)
    }

    private func xPosition(for date: Date, in range: (start: Date, end: Date, duration: TimeInterval), totalWidth: CGFloat) -> CGFloat {
        guard range.duration > 0 else { return 0 }
        let ratio = CGFloat(date.timeIntervalSince(range.start) / range.duration)
        return totalWidth * min(max(ratio, 0), 1)
    }

    private func dotState(for event: ActivityEvent, index: Int, now: Date) -> ProgressEventDot.State {
        if index == currentIndex || (event.startDate <= now && now < event.endDate) {
            return .current
        }
        if event.endDate <= now {
            return .past
        }
        return .future
    }

    private func eventProgress(for event: ActivityEvent, now: Date) -> CGFloat {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        guard duration > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(event.startDate)
        return min(max(CGFloat(elapsed / duration), 0), 1)
    }
}

private struct ProgressEventDot: View {
    enum State {
        case past
        case current
        case future
    }

    let state: State
    let currentProgress: CGFloat

    var body: some View {
        switch state {
        case .past:
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(Color.black.opacity(0.75))
                    .frame(width: 3.5, height: 3.5)
            }
        case .current:
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.78))
                    .frame(width: 18, height: 18)
                Circle()
                    .stroke(Color.orange.opacity(0.24), lineWidth: 2.5)
                    .frame(width: 18, height: 18)
                Circle()
                    .trim(from: 0, to: max(currentProgress, 0.02))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            .shadow(color: Color.orange.opacity(0.35), radius: 5)
        case .future:
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.72))
                    .frame(width: 16, height: 16)
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 2)
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 4.5, height: 4.5)
            }
        }
    }
}

// MARK: - Countdown Helpers

@ViewBuilder
private func countdownView(state: TicActivityAttributes.ContentState) -> some View {
    let now = Date()

    if let ci = state.currentIndex, ci < state.events.count {
        let event = state.events[ci]
        if state.events.count == 1 || state.nextIndex == nil {
            // 일정 1개이거나 다음 일정 없음: 현재 일정 남은 시간
            Text(timerInterval: event.startDate...event.endDate, countsDown: true)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.orange)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else if let ni = state.nextIndex, ni < state.events.count {
            // 여러 일정 + 다음 일정 존재: 다음 일정까지
            let nextEvent = state.events[ni]
            Text(timerInterval: now...nextEvent.startDate, countsDown: true)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.orange)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    } else if let ni = state.nextIndex, ni < state.events.count {
        // 빈 시간: 다음 일정까지 남은 시간
        let nextEvent = state.events[ni]
        Text(timerInterval: now...nextEvent.startDate, countsDown: true)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.orange)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
    // 모든 일정 종료: 카운트다운 숨김 (아무것도 렌더링하지 않음)
}

@ViewBuilder
private func compactCountdownView(state: TicActivityAttributes.ContentState) -> some View {
    let now = Date()

    if let ci = state.currentIndex, ci < state.events.count {
        let event = state.events[ci]
        if state.events.count == 1 || state.nextIndex == nil {
            Text(timerInterval: event.startDate...event.endDate, countsDown: true)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.orange)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText(countsDown: true))
        } else if let ni = state.nextIndex, ni < state.events.count {
            let nextEvent = state.events[ni]
            Text(timerInterval: now...nextEvent.startDate, countsDown: true)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.orange)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText(countsDown: true))
        }
    } else if let ni = state.nextIndex, ni < state.events.count {
        let nextEvent = state.events[ni]
        Text(timerInterval: now...nextEvent.startDate, countsDown: true)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.orange)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentTransition(.numericText(countsDown: true))
    }
}

// MARK: - Helpers

private func currentOrNextTitle(state: TicActivityAttributes.ContentState) -> String {
    if let ci = state.currentIndex, ci < state.events.count {
        return state.events[ci].title
    }
    if let ni = state.nextIndex, ni < state.events.count {
        return state.events[ni].title
    }
    return state.events.first?.title ?? ""
}

private func overallProgress(events: [ActivityEvent]) -> CGFloat {
    guard let first = events.first, let last = events.last else { return 0 }
    let total = last.endDate.timeIntervalSince(first.startDate)
    guard total > 0 else { return 0 }
    let elapsed = Date().timeIntervalSince(first.startDate)
    return min(max(CGFloat(elapsed / total), 0), 1)
}

private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func timeRange(_ event: ActivityEvent) -> String {
    "\(formatTime(event.startDate))-\(formatTime(event.endDate))"
}

private func deepLinkURL(for events: [ActivityEvent]) -> URL {
    let date = events.first?.startDate ?? Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return URL(string: "tic://day?date=\(formatter.string(from: date))")!
}
