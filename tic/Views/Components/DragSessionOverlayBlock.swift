import SwiftUI

struct DragSessionOverlayBlock: View {
    let item: TicItem
    let frame: CGRect

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var backgroundColor: Color {
        Color(cgColor: item.calendarColor)
    }

    var body: some View {
        HStack(spacing: 3) {
            if item.isReminder {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                    .opacity(0.9)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .strikethrough(item.isCompleted)
                    .lineLimit(max(frame.height, 16) < 30 ? 1 : 2)
                if frame.height >= 40, let startDate = item.startDate {
                    Text(timeFormatter.string(from: startDate))
                        .font(.system(size: 9))
                        .opacity(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: frame.width, height: max(frame.height, 16), alignment: .topLeading)
        .background(backgroundColor.opacity(item.isCompleted ? 0.4 : 0.92))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
    }
}
