import SwiftUI

struct TimelineView: View {
    var timedItems: [TicItem]
    var layout: [String: LayoutAttributes]
    var selectedDate: Date
    var onEventTap: (TicItem) -> Void
    var onTimeSlotLongPress: (Date) -> Void
    var onEditItem: (TicItem) -> Void
    var onDeleteItem: (TicItem) -> Void
    var onCompleteItem: (TicItem) -> Void

    let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 44

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // 배경: 시간 라인
                    timeLines

                    // 이벤트 블록
                    GeometryReader { geometry in
                        let eventAreaWidth = geometry.size.width - timeColumnWidth
                        ForEach(timedItems, id: \.id) { item in
                            eventBlock(for: item, containerWidth: eventAreaWidth)
                        }
                    }

                    // 현재 시간 표시 (오늘만)
                    if selectedDate.isToday {
                        currentTimeLine
                            .id("nowLine")
                    }

                    // 빈 시간대 꾹 누르기
                    GeometryReader { geometry in
                        let eventAreaWidth = geometry.size.width - timeColumnWidth
                        ForEach(0..<24, id: \.self) { hour in
                            Color.clear
                                .frame(width: eventAreaWidth, height: hourHeight)
                                .contentShape(Rectangle())
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    let calendar = Calendar.current
                                    if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                                        onTimeSlotLongPress(date)
                                    }
                                }
                                .offset(x: timeColumnWidth, y: CGFloat(hour) * hourHeight)
                        }
                    }
                }
                .frame(height: 24 * hourHeight + 20)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if selectedDate.isToday {
                        let hour = Calendar.current.component(.hour, from: Date())
                        let scrollHour = max(0, hour - 1)
                        withAnimation(.none) {
                            proxy.scrollTo("hour_\(scrollHour)", anchor: .top)
                        }
                    } else {
                        withAnimation(.none) {
                            proxy.scrollTo("hour_8", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Time Lines

    private var timeLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(spacing: 0) {
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: timeColumnWidth, alignment: .trailing)
                        .padding(.trailing, 6)

                    Rectangle()
                        .fill(Color(.separator).opacity(0.5))
                        .frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("hour_\(hour)")
            }
        }
    }

    // MARK: - Event Block

    private func eventBlock(for item: TicItem, containerWidth: CGFloat) -> some View {
        let attrs = layout[item.id]
        let yPos = yPosition(for: item.startDate)
        let height = eventHeight(start: item.startDate, end: item.endDate)
        let width = (attrs?.widthFraction ?? 1.0) * containerWidth
        let xPos = timeColumnWidth + (attrs?.xOffset ?? 0) * containerWidth

        let bgColor: Color = {
            if let cgColor = item.calendarColor as CGColor? {
                return Color(cgColor: cgColor)
            }
            return .gray
        }()

        return Button {
            onEventTap(item)
        } label: {
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
                        .lineLimit(height < 30 ? 1 : 2)

                    if height >= 40, let start = item.startDate {
                        let formatter = {
                            let f = DateFormatter()
                            f.dateFormat = "HH:mm"
                            return f
                        }()
                        Text(formatter.string(from: start))
                            .font(.system(size: 9))
                            .opacity(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(width: max(width - 2, 0), height: max(height - 1, 16), alignment: .topLeading)
            .background(bgColor.opacity(item.isCompleted ? 0.4 : 0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .buttonStyle(.plain)
        .contextMenu {
            Button("수정") { onEditItem(item) }
            Button("삭제", role: .destructive) { onDeleteItem(item) }
        }
        .offset(x: xPos, y: yPos)
    }

    // MARK: - Current Time Line

    private var currentTimeLine: some View {
        GeometryReader { geometry in
            let now = Date()
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)
            let y = (CGFloat(hour) + CGFloat(minute) / 60.0) * hourHeight

            ZStack(alignment: .leading) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .offset(x: timeColumnWidth - 4)

                Rectangle()
                    .fill(.red)
                    .frame(width: geometry.size.width - timeColumnWidth, height: 1)
                    .offset(x: timeColumnWidth)
            }
            .offset(y: y)
        }
        .frame(height: 24 * hourHeight)
    }

    // MARK: - Helpers

    private func yPosition(for date: Date?) -> CGFloat {
        guard let date else { return 0 }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return (CGFloat(hour) + CGFloat(minute) / 60.0) * hourHeight
    }

    private func eventHeight(start: Date?, end: Date?) -> CGFloat {
        guard let start, let end else { return hourHeight }
        let duration = end.timeIntervalSince(start) / 3600.0
        return max(CGFloat(duration) * hourHeight, 16)
    }
}
