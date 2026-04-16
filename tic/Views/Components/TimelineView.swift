import SwiftUI

struct PhantomBlockInfo {
    let hour: Int
    let minute: Int
}

private struct TimelineViewportPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct TimelineScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TimelineView: View {
    var timedItems: [TicItem]
    var layout: [String: LayoutAttributes]
    var selectedDate: Date
    var phantomBlock: PhantomBlockInfo?
    var dragCoordinator: CalendarDragCoordinator
    var onEventTap: (TicItem) -> Void
    var onTimeSlotLongPress: (Date) -> Void
    var onDeleteItem: (TicItem) -> Void
    var onCompleteItem: (TicItem) -> Void
    var onTimelineLayoutChange: (_ frameGlobal: CGRect, _ scrollOffsetY: CGFloat) -> Void

    // Edit mode
    @Binding var editingItemId: String?
    @Binding var showEditToolbar: Bool
    @Binding var isEditingGestureActive: Bool
    var onResizeItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
    var onMoveItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
    var onDuplicateItem: (_ itemId: String) -> Void

    let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 52
    private let eventAreaLeadingInset: CGFloat = 8
    @State private var viewportFrameGlobal: CGRect = .zero
    @State private var scrollOffsetY: CGFloat = 0

    var body: some View {
        GeometryReader { viewportProxy in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        // 1. Time lines + time label long press
                        timeLines

                        // 2. Empty slot long press (disabled in edit mode)
                        emptySlotGestures
                            .allowsHitTesting(editingItemId == nil)

                        // 3. Event blocks (non-editing)
                        GeometryReader { geometry in
                            let eventAreaWidth = geometry.size.width - timeColumnWidth - eventAreaLeadingInset
                            ForEach(timedItems, id: \.id) { item in
                                if item.id != editingItemId {
                                    eventBlock(for: item, containerWidth: eventAreaWidth)
                                }
                            }
                        }
                        .zIndex(1)

                        // 4. Phantom block
                        if let phantom = phantomBlock {
                            GeometryReader { geometry in
                                let yPos = (CGFloat(phantom.hour) + CGFloat(phantom.minute) / 60.0) * hourHeight
                                let eventAreaWidth = geometry.size.width - timeColumnWidth - eventAreaLeadingInset
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.orange.opacity(0.4))
                                    .frame(width: eventAreaWidth - 2, height: hourHeight - 1)
                                    .offset(x: timeColumnWidth + eventAreaLeadingInset, y: yPos)
                            }
                            .zIndex(0.5)
                        }

                        // 5. Current time line (today only)
                        if selectedDate.isToday {
                            currentTimeLine
                                .zIndex(2)
                                .id("nowLine")
                        }

                        // 6. Editing block overlay / placeholder
                        if let editId = editingItemId,
                           let item = timedItems.first(where: { $0.id == editId }) {
                            GeometryReader { geometry in
                                let eventAreaWidth = geometry.size.width - timeColumnWidth - eventAreaLeadingInset
                                let editAttrs = layout[item.id]
                                let editWidth = (editAttrs?.widthFraction ?? 1.0) * eventAreaWidth
                                let editXPos = timeColumnWidth + eventAreaLeadingInset + (editAttrs?.xOffset ?? 0) * eventAreaWidth
                                let baseYPos = yPosition(for: item.startDate)
                                let baseHeight = eventHeight(start: item.startDate, end: item.endDate)
                                let baseFrameGlobal = CGRect(
                                    x: geometry.frame(in: .global).minX + editXPos,
                                    y: geometry.frame(in: .global).minY + baseYPos,
                                    width: max(editWidth - 2, 0),
                                    height: max(baseHeight - 1, 16)
                                )

                                let editBgColor: Color = {
                                    if let cgColor = item.calendarColor as CGColor? {
                                        return Color(cgColor: cgColor)
                                    }
                                    return .gray
                                }()

                                if dragCoordinator.isShowingPlaceholder(for: item.id) {
                                    blockContent(
                                        for: item,
                                        bgColor: editBgColor,
                                        width: max(editWidth - 2, 0),
                                        height: max(baseHeight - 1, 16)
                                    )
                                    .opacity(0.32)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    }
                                    .offset(x: editXPos, y: baseYPos)
                                    .allowsHitTesting(false)
                                } else {
                                    EditableEventBlock(
                                        item: item,
                                        bgColor: editBgColor,
                                        frameWidth: max(editWidth - 2, 0),
                                        baseYPos: baseYPos,
                                        baseHeight: baseHeight,
                                        xPos: editXPos,
                                        hourHeight: hourHeight,
                                        totalTimelineHeight: 24 * hourHeight + 20,
                                        containerWidth: geometry.size.width,
                                        baseFrameGlobal: baseFrameGlobal,
                                        showEditToolbar: $showEditToolbar,
                                        editingItemId: $editingItemId,
                                        isEditingGestureActive: $isEditingGestureActive,
                                        onDeleteItem: onDeleteItem,
                                        onResizeItem: onResizeItem,
                                        onMoveItem: onMoveItem,
                                        onDuplicateItem: onDuplicateItem,
                                        onMoveGestureBegan: { frameGlobal, pointerGlobal in
                                            dragCoordinator.beginDayDrag(
                                                item: item,
                                                sourceFrameGlobal: frameGlobal,
                                                pointerGlobal: pointerGlobal
                                            )
                                        },
                                        onMoveGestureChanged: { pointerGlobal in
                                            dragCoordinator.updateDayDrag(pointerGlobal: pointerGlobal)
                                        },
                                        onMoveGestureEnded: {
                                            if let commit = dragCoordinator.completeLocalDrag() {
                                                onMoveItem(item.id, commit.start, commit.end)
                                            }
                                        }
                                    )
                                }
                            }
                            .zIndex(3)
                        }
                    }
                    .frame(height: 24 * hourHeight + 20)
                    .background {
                        GeometryReader { contentGeometry in
                            Color.clear.preference(
                                key: TimelineScrollOffsetPreferenceKey.self,
                                value: -contentGeometry.frame(in: .named("timelineScroll")).minY
                            )
                        }
                    }
                    // Tap to dismiss edit mode — only when NOT dragging (via background layer)
                    .background {
                        if editingItemId != nil && !isEditingGestureActive {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingItemId = nil
                                    showEditToolbar = false
                                }
                        }
                    }
                }
                .coordinateSpace(name: "timelineScroll")
                .background {
                    Color.clear.preference(
                        key: TimelineViewportPreferenceKey.self,
                        value: viewportProxy.frame(in: .global)
                    )
                }
                .onPreferenceChange(TimelineViewportPreferenceKey.self) { value in
                    viewportFrameGlobal = value
                    onTimelineLayoutChange(value, scrollOffsetY)
                }
                .onPreferenceChange(TimelineScrollOffsetPreferenceKey.self) { value in
                    scrollOffsetY = value
                    onTimelineLayoutChange(viewportFrameGlobal, value)
                }
                .scrollDisabled(isEditingGestureActive || dragCoordinator.isSessionVisible)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if selectedDate.isToday {
                            let hour = Calendar.current.component(.hour, from: Date())
                            withAnimation(.none) { proxy.scrollTo("hour_\(max(0, hour - 1))", anchor: .top) }
                        } else {
                            withAnimation(.none) { proxy.scrollTo("hour_8", anchor: .top) }
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
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5) {
                            let calendar = Calendar.current
                            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                                onTimeSlotLongPress(date)
                            }
                        }
                        .allowsHitTesting(editingItemId == nil)

                    Rectangle()
                        .fill(Color(.separator).opacity(0.5))
                        .frame(height: 0.5)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("hour_\(hour)")
            }
        }
    }

    // MARK: - Empty Slot Gestures

    private var emptySlotGestures: some View {
        GeometryReader { geometry in
            let eventAreaWidth = geometry.size.width - timeColumnWidth - eventAreaLeadingInset
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
                    .offset(x: timeColumnWidth + eventAreaLeadingInset, y: CGFloat(hour) * hourHeight)
            }
        }
    }

    // MARK: - Event Block (non-editing)

    @ViewBuilder
    private func eventBlock(for item: TicItem, containerWidth: CGFloat) -> some View {
        let attrs = layout[item.id]
        let yPos = yPosition(for: item.startDate)
        let height = eventHeight(start: item.startDate, end: item.endDate)
        let width = (attrs?.widthFraction ?? 1.0) * containerWidth
        let xPos = timeColumnWidth + eventAreaLeadingInset + (attrs?.xOffset ?? 0) * containerWidth
        let inEditMode = editingItemId != nil

        let bgColor: Color = {
            if let cgColor = item.calendarColor as CGColor? {
                return Color(cgColor: cgColor)
            }
            return .gray
        }()

        let frameW = max(width - 2, 0)
        let frameH = max(height - 1, 16)

        let content = blockContent(for: item, bgColor: bgColor, width: frameW, height: frameH)

        if inEditMode {
            // Other block during edit mode: tap dismisses, long press switches
            content
                .onTapGesture {
                    editingItemId = nil
                    showEditToolbar = false
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    editingItemId = item.id
                    showEditToolbar = true
                }
                .offset(x: xPos, y: yPos)
        } else {
            // Normal mode: tap to edit sheet, long press to enter edit mode
            content
                .onLongPressGesture(minimumDuration: 0.5) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    editingItemId = item.id
                    showEditToolbar = true
                }
                .onTapGesture { onEventTap(item) }
                .offset(x: xPos, y: yPos)
        }
    }

    // MARK: - Block Content

    private func blockContent(for item: TicItem, bgColor: Color, width: CGFloat, height: CGFloat) -> some View {
        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()

        return HStack(spacing: 3) {
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
                    Text(timeFormatter.string(from: start))
                        .font(.system(size: 9))
                        .opacity(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(bgColor.opacity(item.isCompleted ? 0.4 : 0.85))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    .frame(width: geometry.size.width - timeColumnWidth - eventAreaLeadingInset, height: 1)
                    .offset(x: timeColumnWidth + eventAreaLeadingInset)
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
