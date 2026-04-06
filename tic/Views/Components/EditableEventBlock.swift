import SwiftUI

private enum DragType {
    case none, resizeTop, resizeBottom, move
}

struct EditableEventBlock: View {
    let item: TicItem
    let bgColor: Color
    let frameWidth: CGFloat
    let baseYPos: CGFloat
    let baseHeight: CGFloat
    let xPos: CGFloat
    let hourHeight: CGFloat
    let totalTimelineHeight: CGFloat

    @Binding var showEditToolbar: Bool
    @Binding var editingItemId: String?
    var onDeleteItem: (TicItem) -> Void
    var onResizeItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
    var onMoveItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
    var onDuplicateItem: (_ itemId: String) -> Void

    @State private var activeDrag: DragType = .none
    @State private var dragOffset: CGFloat = 0
    @State private var tooltipTime: String?
    @State private var tooltipY: CGFloat = 0

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // Computed visual position/size during drag
    private var visualY: CGFloat {
        switch activeDrag {
        case .resizeTop: return baseYPos + dragOffset
        case .move: return baseYPos + dragOffset
        case .resizeBottom, .none: return baseYPos
        }
    }

    private var visualHeight: CGFloat {
        switch activeDrag {
        case .resizeTop: return max(baseHeight - dragOffset, hourHeight / 2)
        case .resizeBottom: return max(baseHeight + dragOffset, hourHeight / 2)
        case .move, .none: return baseHeight
        }
    }

    private var frameH: CGFloat { max(visualHeight - 1, 16) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Block content + handles + gesture
            blockContent
                .overlay { editHandles }
                .contentShape(Rectangle())
                .onTapGesture { showEditToolbar = false }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { handleDragChanged($0) }
                        .onEnded { handleDragEnded($0) }
                )
                .offset(x: xPos, y: visualY)

            // Toolbar
            if showEditToolbar {
                toolbar
                    .position(x: toolbarX, y: toolbarYPos)
            }

            // Tooltip during resize
            if let tooltipTime, activeDrag == .resizeTop || activeDrag == .resizeBottom {
                Text(tooltipTime)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .position(x: xPos + frameWidth + 40, y: tooltipY)
            }
        }
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
                    .lineLimit(frameH < 30 ? 1 : 2)
                if frameH >= 40, let start = item.startDate {
                    Text(timeFormatter.string(from: start))
                        .font(.system(size: 9))
                        .opacity(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: frameWidth, height: frameH, alignment: .topLeading)
        .background(bgColor.opacity(item.isCompleted ? 0.4 : 0.85))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Handles (visual only)

    private var editHandles: some View {
        ZStack {
            Circle().fill(.white).frame(width: 8, height: 8).shadow(radius: 2)
                .position(x: frameWidth, y: 0)
            Circle().fill(.white).frame(width: 8, height: 8).shadow(radius: 2)
                .position(x: 0, y: frameH)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Toolbar

    private var toolbarX: CGFloat { xPos + frameWidth / 2 }
    private var toolbarYPos: CGFloat {
        let blockBottom = visualY + visualHeight
        let toolbarH: CGFloat = 44
        let showBelow = blockBottom + 8 + toolbarH < totalTimelineHeight
        return showBelow ? blockBottom + 8 + toolbarH / 2 : visualY - 8 - toolbarH / 2
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

    private func handleDragChanged(_ value: DragGesture.Value) {
        if activeDrag == .none {
            let start = value.startLocation
            let distToTop = hypot(start.x - frameWidth, start.y)
            let distToBottom = hypot(start.x, start.y - frameH)
            if distToTop < 24 {
                activeDrag = .resizeTop
            } else if distToBottom < 24 {
                activeDrag = .resizeBottom
            } else {
                activeDrag = .move
            }
        }

        dragOffset = value.translation.height

        if activeDrag == .resizeTop, let startDate = item.startDate {
            let minutesDelta = Int(round(value.translation.height / (hourHeight / 4))) * 15
            if let newStart = Calendar.current.date(byAdding: .minute, value: minutesDelta, to: startDate) {
                tooltipTime = timeFormatter.string(from: snapToQuarterHour(newStart))
                tooltipY = baseYPos + dragOffset
            }
        } else if activeDrag == .resizeBottom, let endDate = item.endDate {
            let minutesDelta = Int(round(value.translation.height / (hourHeight / 4))) * 15
            if let newEnd = Calendar.current.date(byAdding: .minute, value: minutesDelta, to: endDate) {
                tooltipTime = timeFormatter.string(from: snapToQuarterHour(newEnd))
                tooltipY = baseYPos + baseHeight + dragOffset
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let calendar = Calendar.current

        switch activeDrag {
        case .resizeTop:
            if let start = item.startDate, let end = item.endDate {
                let minutesDelta = Int(round(value.translation.height / (hourHeight / 4))) * 15
                if var newStart = calendar.date(byAdding: .minute, value: minutesDelta, to: start) {
                    newStart = snapToQuarterHour(newStart)
                    let maxStart = calendar.date(byAdding: .minute, value: -30, to: end)!
                    if newStart > maxStart { newStart = maxStart }
                    onResizeItem(item.id, newStart, end)
                }
            }
        case .resizeBottom:
            if let start = item.startDate, let end = item.endDate {
                let minutesDelta = Int(round(value.translation.height / (hourHeight / 4))) * 15
                if var newEnd = calendar.date(byAdding: .minute, value: minutesDelta, to: end) {
                    newEnd = snapToQuarterHour(newEnd)
                    let minEnd = calendar.date(byAdding: .minute, value: 30, to: start)!
                    if newEnd < minEnd { newEnd = minEnd }
                    onResizeItem(item.id, start, newEnd)
                }
            }
        case .move:
            if let start = item.startDate, let end = item.endDate {
                let minutesDelta = Int(round(value.translation.height / (hourHeight / 4))) * 15
                let duration = end.timeIntervalSince(start)
                if var newStart = calendar.date(byAdding: .minute, value: minutesDelta, to: start) {
                    newStart = snapToQuarterHour(newStart)
                    let newEnd = newStart.addingTimeInterval(duration)
                    onMoveItem(item.id, newStart, newEnd)
                }
            }
        case .none:
            break
        }

        activeDrag = .none
        dragOffset = 0
        tooltipTime = nil
    }

    // MARK: - Helpers

    private func snapToQuarterHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let snapped = Int(round(Double(minute) / 15.0)) * 15
        let delta = snapped - minute
        return calendar.date(byAdding: .minute, value: delta, to: date) ?? date
    }
}
