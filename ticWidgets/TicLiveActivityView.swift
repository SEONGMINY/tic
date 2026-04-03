import WidgetKit
import SwiftUI
import ActivityKit

struct TicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TicActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("tic")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeRangeText(start: context.state.startDate, end: context.state.endDate))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        Button {
                        } label: {
                            Text("완료")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button {
                        } label: {
                            Text("10분 후 알림")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.2))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 12, height: 12)
            } compactTrailing: {
                Text(context.state.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            } minimal: {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<TicActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("tic")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.orange)
                Spacer()
                Text(timeRangeText(start: context.state.startDate, end: context.state.endDate))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Title
            Text(context.state.title)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(2)

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                } label: {
                    Text("완료")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button {
                } label: {
                    Text("10분 후 알림")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.2))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Helpers

private func timeRangeText(start: Date, end: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
}
