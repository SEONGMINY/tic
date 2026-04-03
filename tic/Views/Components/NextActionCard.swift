import SwiftUI

struct NextActionCard: View {
    var item: TicItem
    var onComplete: () -> Void
    @AppStorage("nextActionCardCollapsed") private var isCollapsed = false

    var body: some View {
        if isCollapsed {
            // 접힌 상태: 작은 바
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed = false
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("다음: \(item.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } else {
            // 펼친 상태
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.orange)
                    .frame(width: 3)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)

                        if let start = item.startDate {
                            Text(timeDescription(for: start))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if item.isReminder {
                        Button(action: onComplete) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(.orange)
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCollapsed = true
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
        }
    }

    private func timeDescription(for start: Date) -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: start)

        if start > now {
            let minutes = Int(start.timeIntervalSince(now) / 60)
            if minutes < 60 {
                return "\(timeString) · \(minutes)분 후 시작"
            } else {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                if remainingMinutes == 0 {
                    return "\(timeString) · \(hours)시간 후 시작"
                }
                return "\(timeString) · \(hours)시간 \(remainingMinutes)분 후 시작"
            }
        } else {
            return "\(timeString) · 진행 중"
        }
    }
}
