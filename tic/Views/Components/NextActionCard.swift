import SwiftUI

struct NextActionCard: View {
    var item: TicItem
    var onComplete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // 좌측 오렌지 바
            RoundedRectangle(cornerRadius: 2)
                .fill(.orange)
                .frame(width: 4)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)

                    if let start = item.startDate {
                        Text(timeDescription(for: start))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if item.isReminder {
                    Button(action: onComplete) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
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
