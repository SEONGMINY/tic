import SwiftUI

struct DayView: View {
    var viewModel: CalendarViewModel
    var dayViewModel: DayViewModel
    var eventKitService: EventKitService
    var onEditItem: (TicItem) -> Void
    var onCreateAtDate: (Date) -> Void

    @State private var showChecklist = false
    @State private var showDeleteAlert = false
    @State private var itemToDelete: TicItem?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: Binding(
                get: { viewModel.selectedDate.startOfDay },
                set: { newDate in
                    viewModel.selectedDate = newDate
                }
            )) {
                ForEach(dayPages(), id: \.self) { date in
                    dayContent(for: date)
                        .tag(date)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: viewModel.selectedDate) { _, _ in
                Task {
                    await dayViewModel.loadItems(for: viewModel.selectedDate, service: eventKitService)
                }
            }

            // FAB
            if !dayViewModel.timelessReminders.isEmpty {
                Button {
                    showChecklist = true
                } label: {
                    Image(systemName: "checklist")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.orange)
                        .clipShape(Circle())
                        .shadow(radius: 4, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .task {
            await dayViewModel.loadItems(for: viewModel.selectedDate, service: eventKitService)
        }
        .onChange(of: eventKitService.lastChangeDate) { _, _ in
            Task {
                await dayViewModel.loadItems(for: viewModel.selectedDate, service: eventKitService)
            }
        }
        .sheet(isPresented: $showChecklist) {
            ChecklistSheet(
                reminders: dayViewModel.timelessReminders,
                onToggle: { item in
                    try? eventKitService.complete(item)
                },
                onEdit: { item in
                    showChecklist = false
                    onEditItem(item)
                },
                onDelete: { item in
                    itemToDelete = item
                    showDeleteAlert = true
                }
            )
        }
        .alert("이 일정을 삭제하시겠습니까?", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) {
                if let item = itemToDelete {
                    try? eventKitService.delete(item)
                }
                itemToDelete = nil
            }
            Button("취소", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("Apple Calendar/Reminders에서도 삭제됩니다.")
        }
    }

    // MARK: - Day Content

    private func dayContent(for date: Date) -> some View {
        VStack(spacing: 0) {
            // 날짜 헤더
            dateHeader(for: date)

            // 다음 행동 카드 (오늘만)
            if date.isToday, let next = dayViewModel.nextAction {
                NextActionCard(item: next) {
                    try? eventKitService.complete(next)
                }
                .padding(.vertical, 8)
            }

            // 종일 이벤트
            if !dayViewModel.allDayItems.isEmpty {
                allDaySection
            }

            // 타임라인
            TimelineView(
                timedItems: dayViewModel.timedItems,
                layout: dayViewModel.computeLayout(containerWidth: UIScreen.main.bounds.width - 52),
                selectedDate: date,
                onEventTap: { item in
                    onEditItem(item)
                },
                onTimeSlotLongPress: { date in
                    onCreateAtDate(date)
                },
                onEditItem: { item in
                    onEditItem(item)
                },
                onDeleteItem: { item in
                    itemToDelete = item
                    showDeleteAlert = true
                },
                onCompleteItem: { item in
                    try? eventKitService.complete(item)
                }
            )
        }
    }

    // MARK: - Date Header

    private func dateHeader(for date: Date) -> some View {
        HStack(spacing: 8) {
            Text("\(date.day)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(date.isToday ? .orange : .primary)

            VStack(alignment: .leading, spacing: 0) {
                let weekdayNames = ["", "일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]
                Text(weekdayNames[date.weekday])
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - All Day Section

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(dayViewModel.allDayItems) { item in
                Button {
                    onEditItem(item)
                } label: {
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
        .padding(.bottom, 4)
    }

    // MARK: - Pages

    private func dayPages() -> [Date] {
        let center = viewModel.selectedDate.startOfDay
        return (-7...7).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: center)?.startOfDay
        }
    }
}
