import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var calendarSelections: [CalendarSelection]
    @State private var viewModel = CalendarViewModel()
    @State private var eventKitService = EventKitService()
    @State private var dayViewModel = DayViewModel()
    @State private var notificationService = NotificationService()
    @State private var eventFormViewModel = EventFormViewModel()
    @State private var liveActivityService = LiveActivityService()
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showEventForm = false
    private let liveActivityTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            scopeView
                .gesture(pinchGesture)
                .animation(.easeInOut(duration: 0.3), value: viewModel.scope)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        leadingNavItem
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        trailingNavItems
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(eventKitService: eventKitService)
                        .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showEventForm) {
                    EventFormView(
                        viewModel: eventFormViewModel,
                        eventKitService: eventKitService,
                        notificationService: notificationService,
                        onDismiss: { showEventForm = false }
                    )
                }
                .navigationDestination(isPresented: $showSearch) {
                    SearchView(
                        eventKitService: eventKitService,
                        notificationService: notificationService
                    )
                }
        }
        .task {
            await eventKitService.requestCalendarAccess()
            await eventKitService.requestReminderAccess()
            eventKitService.startObservingChanges()
            applyCalendarSelections()
        }
        .onChange(of: calendarSelections.map(\.isEnabled)) {
            applyCalendarSelections()
        }
        .onReceive(liveActivityTimer) { _ in
            Task { await checkLiveActivity() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ticDeepLinkDate)) { notification in
            if let date = notification.userInfo?["date"] as? Date {
                viewModel.selectedDate = date
                viewModel.scope = .day
            }
        }
    }

    // MARK: - Scope View

    @ViewBuilder
    private var scopeView: some View {
        switch viewModel.scope {
        case .year:
            YearView(viewModel: viewModel, eventKitService: eventKitService)
        case .month:
            MonthView(viewModel: viewModel, eventKitService: eventKitService)
        case .day:
            DayView(
                viewModel: viewModel,
                dayViewModel: dayViewModel,
                eventKitService: eventKitService,
                onEditItem: { item in
                    eventFormViewModel.prepareForEdit(item, service: eventKitService)
                    showEventForm = true
                },
                onCreateAtDate: { date in
                    eventFormViewModel.prepareForCreate(at: date)
                    showEventForm = true
                }
            )
        }
    }

    // MARK: - Navigation Bar

    @ViewBuilder
    private var leadingNavItem: some View {
        switch viewModel.scope {
        case .year:
            Button {
                viewModel.goToToday()
            } label: {
                Text("\(viewModel.displayedYear)년")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        case .month:
            Button {
                viewModel.goToToday()
            } label: {
                Text("\(viewModel.displayedMonth.year)년")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        case .day:
            Button {
                viewModel.scope = .month
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("\(viewModel.selectedDate.month)월")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            }
        }
    }

    private var trailingNavItems: some View {
        HStack(spacing: 16) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
            }
            Button {
                eventFormViewModel.prepareForCreate()
                showEventForm = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Pinch Gesture

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                withAnimation(.easeInOut(duration: 0.3)) {
                    if value.magnification < 0.7 {
                        // zoom out
                        switch viewModel.scope {
                        case .day: viewModel.scope = .month
                        case .month: viewModel.scope = .year
                        case .year: break
                        }
                    } else if value.magnification > 1.5 {
                        // zoom in
                        switch viewModel.scope {
                        case .year: viewModel.scope = .month
                        case .month: viewModel.scope = .day
                        case .day: break
                        }
                    }
                }
            }
    }

    // MARK: - Live Activity 자동 시작

    private func checkLiveActivity() async {
        let now = Date()
        let items = await eventKitService.fetchAllItems(for: now)
        let upcoming = items.filter { item in
            guard let start = item.startDate, let end = item.endDate else { return false }
            let minutesBefore = start.timeIntervalSince(now) / 60
            return minutesBefore <= 30 && end > now && !item.isAllDay
        }.first

        if let next = upcoming {
            if !liveActivityService.isActivityActive {
                try? liveActivityService.start(for: next)
            }
        } else if liveActivityService.isActivityActive {
            liveActivityService.endAll()
        }
    }

    // MARK: - CalendarSelection 반영

    private func applyCalendarSelections() {
        if calendarSelections.isEmpty {
            eventKitService.enabledCalendarIdentifiers = nil
        } else {
            let enabled = calendarSelections.filter(\.isEnabled).map(\.calendarIdentifier)
            let disabled = calendarSelections.filter { !$0.isEnabled }.map(\.calendarIdentifier)
            if disabled.isEmpty {
                eventKitService.enabledCalendarIdentifiers = nil
            } else {
                // 모든 캘린더 중 비활성화되지 않은 것만 포함
                let allCalIds = eventKitService.availableCalendars().map(\.calendarIdentifier)
                let allRemIds = eventKitService.availableReminderLists().map(\.calendarIdentifier)
                let allIds = Set(allCalIds + allRemIds)
                let disabledSet = Set(disabled)
                eventKitService.enabledCalendarIdentifiers = allIds.subtracting(disabledSet)
            }
        }
    }
}
