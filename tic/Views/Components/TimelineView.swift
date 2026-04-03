import SwiftUI

struct TimelineView: View {
    var timedItems: [TicItem]
    var layout: [String: LayoutAttributes]
    var selectedDate: Date
    var onEventTap: (TicItem) -> Void
    var onTimeSlotLongPress: (Date) -> Void

    let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 52

    var body: some View {
        GeometryReader { geometry in
            let eventAreaWidth = geometry.size.width - timeColumnWidth

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // 배경: 시간 라인
                        timeLines

                        // 전경: 이벤트 블록
                        ForEach(timedItems, id: \.id) { item in
                            eventBlock(for: item, containerWidth: eventAreaWidth)
                        }

                        // 현재 시간 표시 (오늘만)
                        if selectedDate.isToday {
                            currentTimeLine(containerWidth: geometry.size.width)
                                .id("nowLine")
                        }

                        // 빈 시간대 꾹 누르기 (시간대별 타겟)
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
                    .frame(width: geometry.size.width, height: 24 * hourHeight)
                }
                .onAppear {
                    if selectedDate.isToday {
                        let hour = Calendar.current.component(.hour, from: Date())
                        let scrollHour = max(0, hour - 1)
                        proxy.scrollTo("hour_\(scrollHour)", anchor: .top)
                    } else {
                        proxy.scrollTo("hour_8", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Time Lines

    private var timeLines: some View {
        ForEach(0..<24, id: \.self) { hour in
            HStack(spacing: 0) {
                Text(String(format: "%02d:00", hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: timeColumnWidth, alignment: .trailing)
                    .padding(.trailing, 8)

                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)
            }
            .offset(y: CGFloat(hour) * hourHeight)
            .id("hour_\(hour)")
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(height < 30 ? 1 : 2)

                    if height >= 40, let start = item.startDate {
                        let formatter = {
                            let f = DateFormatter()
                            f.dateFormat = "HH:mm"
                            return f
                        }()
                        Text(formatter.string(from: start))
                            .font(.caption2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(width: max(width - 2, 0), height: max(height - 1, 16), alignment: .topLeading)
            .background(bgColor.opacity(0.8))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .offset(x: xPos, y: yPos)
    }

    // MARK: - Current Time Line

    private func currentTimeLine(containerWidth: CGFloat) -> some View {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let y = (CGFloat(hour) + CGFloat(minute) / 60.0) * hourHeight

        return ZStack(alignment: .leading) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .offset(x: timeColumnWidth - 4)

            Rectangle()
                .fill(.red)
                .frame(width: containerWidth - timeColumnWidth, height: 1)
                .offset(x: timeColumnWidth)
        }
        .offset(y: y)
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
