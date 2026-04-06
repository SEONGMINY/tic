import SwiftUI

struct CrossDayDragState {
    let item: TicItem
    let originalStart: Date
    let originalEnd: Date
    let originalDate: Date
    var currentOffset: CGSize
    var targetDate: Date
    var targetHour: Int
    var targetMinute: Int
}

struct DayView: View {
    var viewModel: CalendarViewModel
    var dayViewModel: DayViewModel
    var eventKitService: EventKitService
    var eventFormViewModel: EventFormViewModel
    var notificationService: NotificationService
    var onEditItem: (TicItem) -> Void

    @State private var showActionSheet = false
    @State private var showDeleteAlert = false
    @State private var itemToDelete: TicItem?
    @State private var slideDirection: Edge = .trailing
    @State private var contentId = UUID()
    @State private var weekStripId = UUID()

    // Phantom block state
    @State private var phantomBlock: PhantomBlockInfo?
    @State private var showCreateSheet = false
    @State private var createDate: Date?

    // Edit mode state
    @State private var editingItemId: String?
    @State private var showEditToolbar: Bool = true

    // Cross-day drag state
    @State private var crossDayDrag: CrossDayDragState?
    @State private var crossDayLastTransitionX: CGFloat = 0

    @Namespace private var dayAnimation

    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    private var showFAB: Bool {
        !dayViewModel.timedItems.isEmpty ||
        !dayViewModel.allDayItems.isEmpty ||
        !dayViewModel.timelessReminders.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // 주간 스트립 (탭 + 스와이프)
            weekStrip
                .id(weekStripId)
                .transition(.asymmetric(
                    insertion: .move(edge: slideDirection),
                    removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
                ))
                .padding(.top, 8)
                .padding(.bottom, 6)

            Divider()

            // 타임라인 영역
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    if !dayViewModel.allDayItems.isEmpty {
                        allDaySection
                    }

                    TimelineView(
                        timedItems: dayViewModel.timedItems,
                        layout: dayViewModel.computeLayout(containerWidth: UIScreen.main.bounds.width - 60),
                        selectedDate: viewModel.selectedDate,
                        phantomBlock: phantomBlock,
                        onEventTap: { item in onEditItem(item) },
                        onTimeSlotLongPress: { date in
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: date)
                            let minute = calendar.component(.minute, from: date)
                            phantomBlock = PhantomBlockInfo(hour: hour, minute: minute)
                            createDate = date
                            eventFormViewModel.prepareForCreate(at: date)
                            showCreateSheet = true
                        },
                        onDeleteItem: { item in
                            itemToDelete = item
                            showDeleteAlert = true
                        },
                        onCompleteItem: { item in
                            try? eventKitService.complete(item)
                        },
                        editingItemId: $editingItemId,
                        showEditToolbar: $showEditToolbar,
                        onResizeItem: { itemId, newStart, newEnd in
                            if let item = dayViewModel.timedItems.first(where: { $0.id == itemId }) {
                                try? eventKitService.moveToDate(item, newStart: newStart, newEnd: newEnd)
                            }
                        },
                        onMoveItem: { itemId, newStart, newEnd in
                            if let item = dayViewModel.timedItems.first(where: { $0.id == itemId }) {
                                try? eventKitService.moveToDate(item, newStart: newStart, newEnd: newEnd)
                            }
                        },
                        onDuplicateItem: { itemId in
                            if let item = dayViewModel.timedItems.first(where: { $0.id == itemId }) {
                                try? eventKitService.duplicate(item)
                            }
                        },
                        onCrossDayDragStart: { item, horizontalTranslation in
                            handleCrossDayDragStart(item: item, horizontalTranslation: horizontalTranslation)
                        }
                    )
                }
                .id(contentId)
                .transition(.asymmetric(
                    insertion: .move(edge: slideDirection),
                    removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
                ))
                // 타임라인 좌우 스와이프
                .gesture(
                    DragGesture(minimumDistance: 60)
                        .onEnded { value in
                            guard editingItemId == nil else { return }
                            let h = abs(value.translation.width)
                            let v = abs(value.translation.height)
                            guard h > v, h > 60 else { return }
                            if value.translation.width > 0 {
                                slideDirection = .leading
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    contentId = UUID()
                                    weekStripId = UUID()
                                    viewModel.selectedDate = viewModel.selectedDate.adding(days: -1)
                                }
                            } else {
                                slideDirection = .trailing
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    contentId = UUID()
                                    weekStripId = UUID()
                                    viewModel.selectedDate = viewModel.selectedDate.adding(days: 1)
                                }
                            }
                        }
                )

                // FAB
                if showFAB {
                    fabButton
                }
            }
            .overlay {
                crossDayDragOverlay
            }
        }
        .task {
            await dayViewModel.loadItems(for: viewModel.selectedDate, service: eventKitService)
        }
        .onChange(of: viewModel.selectedDate) { _, _ in
            Task {
                await dayViewModel.loadItems(for: viewModel.selectedDate, service: eventKitService)
            }
        }
        .onChange(of: eventKitService.lastChangeDate) { _, _ in
            Task {
                await dayViewModel.loadItems(for: viewModel.selectedDate, service: eventKitService)
            }
        }
        .sheet(isPresented: $showActionSheet) {
            ActionListSheet(
                nextAction: viewModel.selectedDate.isToday ? dayViewModel.nextAction : nil,
                allDayItems: dayViewModel.allDayItems,
                timedItems: dayViewModel.timedItems,
                reminders: dayViewModel.timelessReminders,
                eventKitService: eventKitService,
                onEdit: { item in
                    showActionSheet = false
                    onEditItem(item)
                },
                onDelete: { item in
                    itemToDelete = item
                    showDeleteAlert = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreateSheet, onDismiss: {
            phantomBlock = nil
            createDate = nil
        }) {
            EventFormView(
                viewModel: eventFormViewModel,
                eventKitService: eventKitService,
                notificationService: notificationService,
                onDismiss: { showCreateSheet = false }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("이 일정을 삭제하시겠습니까?", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) {
                if let item = itemToDelete { try? eventKitService.delete(item) }
                itemToDelete = nil
            }
            Button("취소", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("Apple Calendar/Reminders에서도 삭제됩니다.")
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            showActionSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                if let count = totalItemCount {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.orange)
            .clipShape(Capsule())
            .shadow(radius: 4, y: 2)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
    }

    private var totalItemCount: Int? {
        let count = dayViewModel.timedItems.count + dayViewModel.allDayItems.count + dayViewModel.timelessReminders.count
        return count > 0 ? count : nil
    }

    // MARK: - Week Strip (페이지 스와이프 + 애니메이션)

    private var weekStrip: some View {
        let weekDates = currentWeekDates()
        return HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { date in
                let isSelected = date.isSameDay(as: viewModel.selectedDate)
                let isToday = date.isToday

                Button {
                    let direction: Edge = date > viewModel.selectedDate ? .trailing : .leading
                    slideDirection = direction
                    withAnimation(.easeInOut(duration: 0.25)) {
                        contentId = UUID()
                        weekStripId = UUID()
                        viewModel.selectedDate = date
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(weekdays[Calendar.current.component(.weekday, from: date) - 1])
                            .font(.system(size: 11))
                            .foregroundStyle(isToday ? .orange : .secondary)

                        Text(verbatim: "\(date.day)")
                            .font(.system(size: 17, weight: isSelected ? .bold : .regular))
                            .foregroundStyle(
                                isSelected && isToday ? .white :
                                isSelected ? Color(.systemBackground) :
                                isToday ? .orange : .primary
                            )
                            .frame(width: 34, height: 34)
                            .background {
                                if isSelected && isToday {
                                    Circle().fill(.orange)
                                        .matchedGeometryEffect(id: "dayIndicator", in: dayAnimation)
                                } else if isSelected {
                                    Circle().fill(Color(.label))
                                        .matchedGeometryEffect(id: "dayIndicator", in: dayAnimation)
                                }
                            }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let h = abs(value.translation.width)
                    let v = abs(value.translation.height)
                    guard h > v else { return }

                    if value.translation.width > 30 {
                        slideDirection = .leading
                        withAnimation(.easeInOut(duration: 0.25)) {
                            contentId = UUID()
                            weekStripId = UUID()
                            viewModel.selectedDate = viewModel.selectedDate.adding(days: -7)
                        }
                    } else if value.translation.width < -30 {
                        slideDirection = .trailing
                        withAnimation(.easeInOut(duration: 0.25)) {
                            contentId = UUID()
                            weekStripId = UUID()
                            viewModel.selectedDate = viewModel.selectedDate.adding(days: 7)
                        }
                    }
                }
        )
    }

    // MARK: - All Day Section

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(dayViewModel.allDayItems) { item in
                Button { onEditItem(item) } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(cgColor: item.calendarColor))
                            .frame(width: 8, height: 8)
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(cgColor: item.calendarColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("수정") { onEditItem(item) }
                    Button("삭제", role: .destructive) {
                        itemToDelete = item
                        showDeleteAlert = true
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Cross-Day Drag

    private func handleCrossDayDragStart(item: TicItem, horizontalTranslation: CGFloat) {
        guard let start = item.startDate, let end = item.endDate else { return }

        let direction: Int = horizontalTranslation > 0 ? -1 : 1
        let newDate = viewModel.selectedDate.adding(days: direction)

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: start)
        let minute = calendar.component(.minute, from: start)

        crossDayDrag = CrossDayDragState(
            item: item,
            originalStart: start,
            originalEnd: end,
            originalDate: viewModel.selectedDate,
            currentOffset: .zero,
            targetDate: newDate,
            targetHour: hour,
            targetMinute: minute
        )
        crossDayLastTransitionX = 0

        slideDirection = direction > 0 ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.25)) {
            contentId = UUID()
            weekStripId = UUID()
            viewModel.selectedDate = newDate
        }
    }

    @ViewBuilder
    private var crossDayDragOverlay: some View {
        if let drag = crossDayDrag {
            let blockColor = Color(cgColor: drag.item.calendarColor)
            let duration = drag.originalEnd.timeIntervalSince(drag.originalStart) / 3600.0
            let blockHeight = max(CGFloat(duration) * 60, 16)

            RoundedRectangle(cornerRadius: 4)
                .fill(blockColor.opacity(0.85))
                .overlay(alignment: .topLeading) {
                    Text(drag.item.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(4)
                }
                .frame(
                    width: UIScreen.main.bounds.width - 60,
                    height: blockHeight
                )
                .shadow(radius: 8, y: 4)
                .position(
                    x: UIScreen.main.bounds.width / 2 + 4,
                    y: 200 + drag.currentOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            crossDayDrag?.currentOffset = value.translation

                            // Additional date transition on continued horizontal drag
                            let deltaX = value.translation.width - crossDayLastTransitionX
                            if abs(deltaX) > 60 {
                                let dir: Int = deltaX > 0 ? -1 : 1
                                let nextDate = (crossDayDrag?.targetDate ?? viewModel.selectedDate).adding(days: dir)
                                crossDayDrag?.targetDate = nextDate
                                crossDayLastTransitionX = value.translation.width

                                slideDirection = dir > 0 ? .trailing : .leading
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    contentId = UUID()
                                    weekStripId = UUID()
                                    viewModel.selectedDate = nextDate
                                }
                            }
                        }
                        .onEnded { value in
                            // Cancel: small translation → return to original date
                            if abs(value.translation.height) < 20 && abs(value.translation.width) < 30 {
                                if let d = crossDayDrag, d.targetDate != d.originalDate {
                                    let dir: Edge = d.originalDate < d.targetDate ? .leading : .trailing
                                    slideDirection = dir
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        contentId = UUID()
                                        weekStripId = UUID()
                                        viewModel.selectedDate = d.originalDate
                                    }
                                }
                                crossDayDrag = nil
                                // editingItemId is kept — edit mode maintained
                                return
                            }
                            commitCrossDayDrag(finalTranslation: value.translation)
                        }
                )
        }
    }

    private func commitCrossDayDrag(finalTranslation: CGSize) {
        guard let drag = crossDayDrag else { return }

        let hourHeight: CGFloat = 60
        let baseY = CGFloat(drag.targetHour) * hourHeight + CGFloat(drag.targetMinute) / 60.0 * hourHeight
        let finalY = max(0, baseY + finalTranslation.height)

        let hour = max(0, min(23, Int(finalY / hourHeight)))
        let minuteFraction = (finalY - CGFloat(hour) * hourHeight) / hourHeight
        let minute = max(0, min(45, Int(round(minuteFraction * 4)) * 15))

        let calendar = Calendar.current
        let duration = drag.originalEnd.timeIntervalSince(drag.originalStart)
        var components = calendar.dateComponents([.year, .month, .day], from: drag.targetDate)
        components.hour = hour
        components.minute = minute

        if let newStart = calendar.date(from: components) {
            let newEnd = newStart.addingTimeInterval(duration)
            try? eventKitService.moveToDate(drag.item, newStart: newStart, newEnd: newEnd)
        }

        crossDayDrag = nil
        editingItemId = nil
    }

    // MARK: - Helpers

    private func currentWeekDates() -> [Date] {
        let calendar = Calendar.current
        let selected = viewModel.selectedDate
        let weekday = calendar.component(.weekday, from: selected)
        let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: selected)!
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfWeek)
        }
    }
}

// MARK: - Action List Sheet

private struct ActionListSheet: View {
    let nextAction: TicItem?
    let allDayItems: [TicItem]
    let timedItems: [TicItem]
    let reminders: [TicItem]
    let eventKitService: EventKitService
    let onEdit: (TicItem) -> Void
    let onDelete: (TicItem) -> Void

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if !allDayItems.isEmpty {
                    Section("종일") {
                        ForEach(allDayItems) { item in
                            eventRow(item, isNext: false)
                        }
                    }
                }

                if !timedItems.isEmpty {
                    Section("일정") {
                        ForEach(timedItems) { item in
                            eventRow(item, isNext: nextAction?.id == item.id)
                        }
                    }
                }

                if !reminders.isEmpty {
                    Section("체크리스트") {
                        ForEach(reminders) { item in
                            HStack(spacing: 10) {
                                Button {
                                    try? eventKitService.complete(item)
                                } label: {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                                }

                                Text(item.title)
                                    .font(.system(size: 14))
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onEdit(item) }
                            .contextMenu {
                                Button("수정") { onEdit(item) }
                                Button("삭제", role: .destructive) { onDelete(item) }
                            }
                        }
                    }
                }

                if allDayItems.isEmpty && timedItems.isEmpty && reminders.isEmpty {
                    Text("오늘 일정이 없습니다")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
            .navigationTitle("오늘의 일정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func eventRow(_ item: TicItem, isNext: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isNext ? Color.orange : Color(cgColor: item.calendarColor))
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                if isNext {
                    Text("다음")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Text(item.title)
                    .font(.system(size: 14, weight: isNext ? .bold : .regular))
                    .lineLimit(1)
            }

            Spacer()

            if let start = item.startDate, !item.isAllDay {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(timeFormatter.string(from: start))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(isNext ? .orange : .secondary)
                        .monospacedDigit()
                    if let end = item.endDate {
                        Text(timeFormatter.string(from: end))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }

            if item.isReminder {
                Button {
                    try? eventKitService.complete(item)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(item) }
        .listRowBackground(isNext ? Color.orange.opacity(0.08) : nil)
        .contextMenu {
            Button("수정") { onEdit(item) }
            Button("삭제", role: .destructive) { onDelete(item) }
            if item.isReminder {
                Button("완료") { try? eventKitService.complete(item) }
            }
        }
    }
}
