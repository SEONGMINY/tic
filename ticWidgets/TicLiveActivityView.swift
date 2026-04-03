import WidgetKit
import SwiftUI
import ActivityKit

struct TicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TicActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.8))
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange)
                        Text("tic")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        JourneyProgressView(
                            startDate: context.state.startDate,
                            endDate: context.state.endDate,
                            showTimes: true,
                            height: 4
                        )

                        HStack {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 7, height: 7)
                                Text("진행 중")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.orange)
                            }
                            Spacer()
                            Text(remainingTimeCompact(start: context.state.startDate, end: context.state.endDate) + " 남음")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text(context.state.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
            } compactTrailing: {
                Text(remainingTimeCompact(start: context.state.startDate, end: context.state.endDate))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .monospacedDigit()
            } minimal: {
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progressValue(start: context.state.startDate, end: context.state.endDate))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 16, height: 16)
            }
        }
    }
}

// MARK: - Journey Progress View

struct JourneyProgressView: View {
    let startDate: Date
    let endDate: Date
    let showTimes: Bool
    let height: CGFloat

    var body: some View {
        let progress = progressValue(start: startDate, end: endDate)

        VStack(spacing: 6) {
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let iconPosition = totalWidth * progress

                ZStack(alignment: .leading) {
                    // 시작 점
                    Circle()
                        .fill(Color.orange)
                        .frame(width: height + 4, height: height + 4)
                        .position(x: 0, y: height / 2)

                    // 진행된 부분 — 오렌지 실선
                    if progress > 0 {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: height / 2))
                            path.addLine(to: CGPoint(x: iconPosition, y: height / 2))
                        }
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: height, lineCap: .round))
                    }

                    // 남은 부분 — 회색 점선
                    if progress < 1 {
                        Path { path in
                            path.move(to: CGPoint(x: iconPosition, y: height / 2))
                            path.addLine(to: CGPoint(x: totalWidth, y: height / 2))
                        }
                        .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: height, lineCap: .round, dash: [4, 4]))
                    }

                    // 종료 점
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                        .frame(width: height + 4, height: height + 4)
                        .position(x: totalWidth, y: height / 2)

                    // 시계 아이콘 — 현재 진행 위치
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .position(x: iconPosition, y: height / 2)
                }
            }
            .frame(height: max(height + 4, 16))

            if showTimes {
                HStack {
                    Text(formatTime(startDate))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(formatTime(endDate))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<TicActivityAttributes>

    var body: some View {
        VStack(spacing: 14) {
            // 상단: tic 로고(좌) + 일정 제목(우)
            HStack {
                Text("tic")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.orange)
                Spacer()
                Text(context.state.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
            }

            // 중앙: 시각적 여정 프로그레스
            JourneyProgressView(
                startDate: context.state.startDate,
                endDate: context.state.endDate,
                showTimes: true,
                height: 4
            )

            // 하단 상태
            HStack {
                Text("시작됨 " + formatTime(context.state.startDate))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(remainingTimeCompact(start: context.state.startDate, end: context.state.endDate) + " 남음")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .monospacedDigit()
            }

            // 액션 버튼
            HStack(spacing: 10) {
                Button(intent: CompleteEventIntent(eventIdentifier: context.attributes.eventIdentifier)) {
                    Text("완료")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                Button(intent: SnoozeEventIntent(eventIdentifier: context.attributes.eventIdentifier)) {
                    Text("10분 후 알림")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
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

private func remainingTimeCompact(start: Date, end: Date) -> String {
    let now = Date()
    let target = now < start ? start : end
    let remaining = Int(target.timeIntervalSince(now) / 60)
    if remaining <= 0 { return "0분" }
    if remaining < 60 { return "\(remaining)분" }
    let h = remaining / 60
    let m = remaining % 60
    if m == 0 { return "\(h)시간" }
    return "\(h):\(String(format: "%02d", m))"
}

private func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}
