import SwiftUI

private enum DragType {
    case none, resizeTop, resizeBottom, move
}

struct EditableEventBlock: View {
    let item: TicItem
    let dragCoordinator: CalendarDragCoordinator
    let bgColor: Color
    let frameWidth: CGFloat
    let baseYPos: CGFloat
    let baseHeight: CGFloat
    let xPos: CGFloat
    let hourHeight: CGFloat
    let totalTimelineHeight: CGFloat
    let containerWidth: CGFloat
    let baseFrameGlobal: CGRect

    @Binding var showEditToolbar: Bool
    @Binding var editingItemId: String?
    @Binding var isEditingGestureActive: Bool
    var onDeleteItem: (TicItem) -> Void
    var onResizeItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
    var onMoveItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
    var onDuplicateItem: (_ itemId: String) -> Void
    var onMoveGestureBegan: ((_ sourceFrameGlobal: CGRect, _ startPointerGlobal: CGPoint, _ currentPointerGlobal: CGPoint) -> Void)?
    var onMoveGestureChanged: ((_ pointerGlobal: CGPoint) -> Void)?
    var onMoveGestureEnded: ((_ pointerGlobal: CGPoint) -> Void)?

    @State private var activeDrag: DragType = .none
    @State private var dragOffset: CGFloat = 0
    @State private var tooltipTime: String?
    @State private var tooltipY: CGFloat = 0
    @State private var externalMoveSessionStarted = false

    private let handleSize: CGFloat = 10
    private let handleHitSize: CGFloat = 32
    private var handleInset: CGFloat { handleHitSize / 2 }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var accessibilityLabelText: String {
        item.title
    }

    private var accessibilityValueText: String {
        guard let start = item.startDate,
              let end = item.endDate else {
            return item.isAllDay ? "all-day" : "untimed"
        }
        return "\(timeFormatter.string(from: start))-\(timeFormatter.string(from: end))"
    }

    // Snapped visual Y position
    private var visualY: CGFloat {
        switch activeDrag {
        case .resizeTop, .move: return baseYPos + dragOffset
        case .resizeBottom, .none: return baseYPos
        }
    }

    // Snapped visual height
    private var visualHeight: CGFloat {
        let minH: CGFloat = 30 // 30 minutes minimum
        switch activeDrag {
        case .resizeTop: return max(baseHeight - dragOffset, minH)
        case .resizeBottom: return max(baseHeight + dragOffset, minH)
        case .move, .none: return baseHeight
        }
    }

    private var clampedFrameH: CGFloat { max(visualHeight - 1, 16) }
    private var usesExternalMoveSession: Bool {
        onMoveGestureBegan != nil && onMoveGestureChanged != nil
    }
    private var localPreviewPresentation: DragOverlayPresentation {
        dragCoordinator.overlayPresentation
    }
    private var localPreviewFrameGlobal: CGRect? {
        dragCoordinator.localPreviewFrameGlobal(for: item.id)
    }
    private var showsLocalMovePreview: Bool {
        localPreviewFrameGlobal != nil
    }
    private var localPreviewOffset: CGSize {
        guard let localPreviewFrameGlobal else { return .zero }
        return CGSize(
            width: localPreviewFrameGlobal.minX - baseFrameGlobal.minX,
            height: localPreviewFrameGlobal.minY - baseFrameGlobal.minY
        )
    }

    var body: some View {
        // Fixed-size container prevents layout recalculation jitter
        ZStack(alignment: .topLeading) {
            blockWithHandles
                .opacity(showsLocalMovePreview ? 0.001 : 1)
                .offset(x: xPos - handleInset, y: visualY - handleInset)

            if showsLocalMovePreview {
                localMovePreview
            }

            // Toolbar
            if showEditToolbar && activeDrag == .none && showsLocalMovePreview == false {
                toolbar
                    .position(x: toolbarX, y: toolbarYPos)
            }

            // Tooltip during resize
            if let tooltipTime, activeDrag == .resizeTop || activeDrag == .resizeBottom {
                tooltipView(time: tooltipTime)
            }
        }
        .frame(width: containerWidth, height: totalTimelineHeight, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }

    // MARK: - Editable Block

    private var blockWithHandles: some View {
        ZStack(alignment: .topLeading) {
            moveBlock
            topResizeHandle
            bottomResizeHandle
        }
        .frame(
            width: frameWidth + handleHitSize,
            height: clampedFrameH + handleHitSize,
            alignment: .topLeading
        )
    }

    private var moveBlock: some View {
        blockContent
            .offset(x: handleInset, y: handleInset)
            .contentShape(Rectangle())
            .highPriorityGesture(moveGesture)
            .onTapGesture { showEditToolbar = false }
    }

    private var localMovePreview: some View {
        blockContent
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .scaleEffect(localPreviewPresentation.overlayScale)
            .opacity(localPreviewPresentation.overlayOpacity)
            .shadow(
                color: .black.opacity(localPreviewPresentation.shadowOpacity),
                radius: localPreviewPresentation.shadowRadius,
                y: localPreviewPresentation.shadowYOffset
            )
            .offset(
                x: xPos + localPreviewOffset.width,
                y: baseYPos + localPreviewOffset.height
            )
            .allowsHitTesting(false)
    }

    // MARK: - Block Content

    private var blockContent: some View {
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
                    .lineLimit(clampedFrameH < 30 ? 1 : 2)
                if clampedFrameH >= 40, let start = item.startDate {
                    Text(timeFormatter.string(from: start))
                        .font(.system(size: 9))
                        .opacity(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: frameWidth, height: clampedFrameH, alignment: .topLeading)
        .background(bgColor.opacity(item.isCompleted ? 0.4 : 0.85))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline-event-\(item.id)")
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
    }

    // MARK: - Handles

    private var topResizeHandle: some View {
        handleView(x: handleInset + frameWidth, y: handleInset)
            .highPriorityGesture(topResizeGesture)
    }

    private var bottomResizeHandle: some View {
        handleView(x: handleInset, y: handleInset + clampedFrameH)
            .highPriorityGesture(bottomResizeGesture)
    }

    private func handleView(x: CGFloat, y: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: handleHitSize, height: handleHitSize)
            Circle()
                .fill(.white)
                .frame(width: handleSize, height: handleSize)
                .shadow(radius: 2)
        }
        .contentShape(Circle())
        .position(x: x, y: y)
    }

    // MARK: - Drag Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                handleDragChanged(value, dragType: .move)
            }
            .onEnded { value in
                handleDragEnded(value, dragType: .move)
            }
    }

    private var topResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                handleDragChanged(value, dragType: .resizeTop)
            }
            .onEnded { value in
                handleDragEnded(value, dragType: .resizeTop)
            }
    }

    private var bottomResizeGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                handleDragChanged(value, dragType: .resizeBottom)
            }
            .onEnded { value in
                handleDragEnded(value, dragType: .resizeBottom)
            }
    }

    // MARK: - Tooltip

    private func tooltipView(time: String) -> some View {
        Text(time)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .position(x: xPos + frameWidth + 40, y: tooltipY)
    }

    // MARK: - Toolbar

    private var toolbarX: CGFloat { xPos + frameWidth / 2 }
    private var toolbarYPos: CGFloat {
        let blockBottom = baseYPos + baseHeight
        let toolbarH: CGFloat = 44
        let showBelow = blockBottom + 8 + toolbarH < totalTimelineHeight
        return showBelow ? blockBottom + 8 + toolbarH / 2 : baseYPos - 8 - toolbarH / 2
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                onDeleteItem(item)
                editingItemId = nil
                showEditToolbar = false
            } label: {
                Label("삭제", systemImage: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            Divider().frame(height: 20)
            Button {
                onDuplicateItem(item.id)
                editingItemId = nil
                showEditToolbar = false
            } label: {
                Label("복제", systemImage: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4, y: 2)
    }

    // MARK: - Drag Handling

    private func handleDragChanged(_ value: DragGesture.Value, dragType: DragType) {
        if activeDrag == .none {
            activeDrag = dragType
            isEditingGestureActive = true
            showEditToolbar = false

            if dragType == .move, usesExternalMoveSession {
                externalMoveSessionStarted = false
            }
        }

        if dragType == .move, usesExternalMoveSession {
            if externalMoveSessionStarted == false {
                externalMoveSessionStarted = true
                onMoveGestureBegan?(
                    baseFrameGlobal,
                    value.startLocation,
                    value.location
                )
            }
            onMoveGestureChanged?(value.location)
            return
        }

        // Snap to 15-minute grid
        let qh = hourHeight / 4
        let snapped = round(value.translation.height / qh) * qh

        // Clamp: prevent resizing below 30 minutes
        switch dragType {
        case .resizeTop:
            let maxOffset = baseHeight - (hourHeight / 2) // 30 min minimum
            dragOffset = min(snapped, maxOffset)
        case .resizeBottom:
            let minOffset = -(baseHeight - (hourHeight / 2))
            dragOffset = max(snapped, minOffset)
        case .move:
            // Clamp to timeline bounds
            let minY = -baseYPos
            let maxY = totalTimelineHeight - baseYPos - baseHeight
            dragOffset = max(minY, min(snapped, maxY))
        case .none:
            break
        }

        // Update tooltip
        updateTooltip()
    }

    private func updateTooltip() {
        let qh = hourHeight / 4
        let minutesDelta = Int(dragOffset / qh) * 15

        if activeDrag == .resizeTop, let startDate = item.startDate {
            if let newTime = Calendar.current.date(byAdding: .minute, value: minutesDelta, to: startDate) {
                tooltipTime = timeFormatter.string(from: newTime)
                tooltipY = visualY
            }
        } else if activeDrag == .resizeBottom, let endDate = item.endDate {
            if let newTime = Calendar.current.date(byAdding: .minute, value: minutesDelta, to: endDate) {
                tooltipTime = timeFormatter.string(from: newTime)
                tooltipY = baseYPos + visualHeight
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, dragType: DragType) {
        defer {
            activeDrag = .none
            isEditingGestureActive = false
            dragOffset = 0
            tooltipTime = nil
            externalMoveSessionStarted = false
        }

        if dragType == .move, usesExternalMoveSession {
            if externalMoveSessionStarted {
                onMoveGestureChanged?(value.location)
                onMoveGestureEnded?(value.location)
            } else {
                showEditToolbar = true
            }
            return
        }

        let calendar = Calendar.current
        let qh = hourHeight / 4
        let minutesDelta = Int(dragOffset / qh) * 15

        guard minutesDelta != 0 else { return }

        switch dragType {
        case .resizeTop:
            if let start = item.startDate, let end = item.endDate {
                if var newStart = calendar.date(byAdding: .minute, value: minutesDelta, to: start) {
                    let maxStart = calendar.date(byAdding: .minute, value: -30, to: end)!
                    if newStart > maxStart { newStart = maxStart }
                    onResizeItem(item.id, newStart, end)
                }
            }
        case .resizeBottom:
            if let start = item.startDate, let end = item.endDate {
                if var newEnd = calendar.date(byAdding: .minute, value: minutesDelta, to: end) {
                    let minEnd = calendar.date(byAdding: .minute, value: 30, to: start)!
                    if newEnd < minEnd { newEnd = minEnd }
                    onResizeItem(item.id, start, newEnd)
                }
            }
        case .move:
            if let start = item.startDate, let end = item.endDate {
                let duration = end.timeIntervalSince(start)
                if let newStart = calendar.date(byAdding: .minute, value: minutesDelta, to: start) {
                    let newEnd = newStart.addingTimeInterval(duration)
                    onMoveItem(item.id, newStart, newEnd)
                }
            }
        case .none:
            break
        }
    }
}
