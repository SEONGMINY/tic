import SwiftUI

private struct OverlayShape: Shape {
    let style: DragOverlayStyle
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        switch style {
        case .timelineCard:
            return RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)
        case .calendarPill:
            return Capsule().path(in: rect)
        }
    }
}

struct DragSessionOverlayBlock: View {
    let item: TicItem
    let frame: CGRect
    let presentation: DragOverlayPresentation

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var backgroundColor: Color {
        Color(cgColor: item.calendarColor)
    }

    private var containerShape: OverlayShape {
        OverlayShape(style: presentation.style, cornerRadius: presentation.cornerRadius)
    }

    var body: some View {
        overlayBody
        .frame(width: frame.width, height: max(frame.height, 16), alignment: .topLeading)
        .background(backgroundColor.opacity(item.isCompleted ? 0.4 : 0.94))
        .foregroundStyle(.white)
        .clipShape(containerShape)
        .overlay {
            containerShape
                .stroke(Color.white.opacity(presentation.style == .calendarPill ? 0.16 : 0.08), lineWidth: 1)
        }
        .scaleEffect(presentation.overlayScale)
        .opacity(presentation.overlayOpacity)
        .shadow(
            color: .black.opacity(presentation.shadowOpacity),
            radius: presentation.shadowRadius,
            y: presentation.shadowYOffset
        )
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private var overlayBody: some View {
        switch presentation.style {
        case .timelineCard:
            timelineCardBody
        case .calendarPill:
            calendarPillBody
        }
    }

    private var timelineCardBody: some View {
        HStack(spacing: 3) {
            if item.isReminder {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                    .opacity(0.9)
            }
            VStack(alignment: .leading, spacing: 2) {
                if presentation.showsTitle {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                        .strikethrough(item.isCompleted)
                        .lineLimit(max(frame.height, 16) < 30 ? 1 : 2)
                }
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
    }

    private var calendarPillBody: some View {
        Color.clear
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .padding(1)
            }
    }

}
