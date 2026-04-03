import WidgetKit
import SwiftUI
import ActivityKit

struct TicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TicActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(.black.opacity(0.75))
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(remainingTimeCompact(start: context.state.startDate, end: context.state.endDate))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.orange)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        // 프로그레스 바 + 시간
                        VStack(spacing: 5) {
                            ProgressBarView(
                                startDate: context.state.startDate,
                                endDate: context.state.endDate
                            )
                            HStack {
                                Text(formatTime(context.state.startDate))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Spacer()
                                Text(formatTime(context.state.endDate))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        // 액션 버튼 (둥근 배경)
                        HStack(spacing: 8) {
                            Button(intent: CompleteEventIntent(eventIdentifier: context.attributes.eventIdentifier)) {
                                Text("완료")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            Button(intent: SnoozeEventIntent(eventIdentifier: context.attributes.eventIdentifier)) {
                                Text("10분 후")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
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

// MARK: - Progress Bar

private struct ProgressBarView: View {
    let startDate: Date
    let endDate: Date

    var body: some View {
        GeometryReader { geometry in
            let progress = progressValue(start: startDate, end: endDate)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 5)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geometry.size.width * progress, 5), height: 5)
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<TicActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            // 상단: tic + 남은 시간
            HStack {
                Text("tic")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orange)
                Spacer()
                Text(remainingTimeCompact(start: context.state.startDate, end: context.state.endDate) + " 남음")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange)
                    .monospacedDigit()
            }

            // 제목
            HStack {
                Text(context.state.title)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }

            // 프로그레스 바 + 시간
            VStack(spacing: 5) {
                ProgressBarView(
                    startDate: context.state.startDate,
                    endDate: context.state.endDate
                )
                HStack {
                    Text(formatTime(context.state.startDate))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(context.state.endDate))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // 액션 버튼 (둥근 배경)
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
