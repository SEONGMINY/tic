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
    @Environment(\.scenePhase) private var scenePhase
    private let liveActivityTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // 커스텀 네비게이션 바
            navBar
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .padding(.top, 4)

            // 메인 컨텐츠
            scopeView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(.spring(duration: 0.35, bounce: 0.05), value: viewModel.scope)
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
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                SearchView(
                    eventKitService: eventKitService,
                    notificationService: notificationService
                )
            }
            .presentationDetents([.large])
        }
        .task {
            await eventKitService.requestCalendarAccess()
            await eventKitService.requestReminderAccess()
            eventKitService.startObservingChanges()
            applyCalendarSelections()
            // 첫 실행 시 Live Activity 체크
            await checkLiveActivity()
        }
        .onChange(of: calendarSelections.map(\.isEnabled)) {
            applyCalendarSelections()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // 포그라운드 복귀 시 Live Activity 체크
                Task { await checkLiveActivity() }
            }
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

    // MARK: - Navigation Bar

    private var navBar: some View {
        HStack {
            leadingNavItem
            Spacer()
            trailingNavItems
        }
    }

    @ViewBuilder
    private var leadingNavItem: some View {
        switch viewModel.scope {
        case .year:
            Button {
                viewModel.goToToday()
            } label: {
                Text(verbatim: "\(viewModel.displayedYear)년")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        case .month:
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.05)) {
                    viewModel.scope = .year
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text(verbatim: "\(viewModel.displayedYear)년")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.primary)
            }
        case .day:
            Button {
                withAnimation(.spring(duration: 0.4, bounce: 0.05)) {
                    viewModel.scope = .month
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text(verbatim: "\(viewModel.selectedDate.month)월 \(viewModel.selectedDate.year)년")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var trailingNavItems: some View {
        HStack(spacing: 14) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
            }
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
            }
            Button {
                eventFormViewModel.prepareForCreate()
                showEventForm = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15))
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Scope View

    @ViewBuilder
    private var scopeView: some View {
        switch viewModel.scope {
        case .year:
            YearView(viewModel: viewModel, eventKitService: eventKitService)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .month:
            MonthView(viewModel: viewModel, eventKitService: eventKitService)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
            .transition(.opacity.combined(with: .scale(scale: 1.02)))
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
            let disabled = calendarSelections.filter { !$0.isEnabled }.map(\.calendarIdentifier)
            if disabled.isEmpty {
                eventKitService.enabledCalendarIdentifiers = nil
            } else {
                let allCalIds = eventKitService.availableCalendars().map(\.calendarIdentifier)
                let allRemIds = eventKitService.availableReminderLists().map(\.calendarIdentifier)
                let allIds = Set(allCalIds + allRemIds)
                let disabledSet = Set(disabled)
                eventKitService.enabledCalendarIdentifiers = allIds.subtracting(disabledSet)
            }
        }
    }
}
