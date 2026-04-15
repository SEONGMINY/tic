import SwiftUI
import SwiftData
import ActivityKit

struct ContentView: View {
    @Query private var calendarSelections: [CalendarSelection]
    @State private var viewModel = CalendarViewModel()
    @State private var eventKitService = EventKitService()
    @State private var dayViewModel = DayViewModel()
    @State private var notificationService = NotificationService()
    @State private var eventFormViewModel = EventFormViewModel()
    @State private var liveActivityService = LiveActivityService()
    @State private var dragCoordinator = CalendarDragCoordinator()
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
                .contentShape(Rectangle())
                .simultaneousGesture(scopePinchGesture, including: .all)
                .animation(.spring(duration: 0.35, bounce: 0.05), value: viewModel.scope)
        }
        .simultaneousGesture(rootDragGesture, including: .all)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        dragCoordinator.updateRootFrame(proxy.frame(in: .global))
                    }
                    .onChange(of: proxy.frame(in: .global)) { _, newValue in
                        dragCoordinator.updateRootFrame(newValue)
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let overlayItem = dragCoordinator.overlayItem,
               let overlayFrame = dragCoordinator.overlayFrameLocal {
                DragSessionOverlayBlock(item: overlayItem, frame: overlayFrame)
                    .zIndex(10)
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
            dragCoordinator.updateVisibleScope(viewModel.scope)
            // 첫 실행 시 Live Activity 체크
            await checkLiveActivity()
        }
        .onChange(of: calendarSelections.map(\.isEnabled)) {
            applyCalendarSelections()
        }
        .onChange(of: viewModel.scope) { _, newScope in
            dragCoordinator.updateVisibleScope(newScope)
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
                applyScopeTransition(.pinchOut)
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
                applyScopeTransition(.pinchOut)
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
        HStack(spacing: 18) {
            Button { showSettings = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            Button {
                eventFormViewModel.prepareForCreate()
                showEventForm = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Scope View

    @ViewBuilder
    private var scopeView: some View {
        switch viewModel.scope {
        case .year:
            YearView(
                viewModel: viewModel,
                eventKitService: eventKitService,
                dragCoordinator: dragCoordinator
            )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .month:
            MonthView(
                viewModel: viewModel,
                eventKitService: eventKitService,
                dragCoordinator: dragCoordinator
            )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .day:
            DayView(
                viewModel: viewModel,
                dayViewModel: dayViewModel,
                eventKitService: eventKitService,
                eventFormViewModel: eventFormViewModel,
                notificationService: notificationService,
                dragCoordinator: dragCoordinator,
                onEditItem: { item in
                    eventFormViewModel.prepareForEdit(item, service: eventKitService)
                    showEventForm = true
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 1.02)))
        }
    }

    private var rootDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard dragCoordinator.shouldHandleDragGlobally else { return }
                dragCoordinator.updateGlobalDrag(pointerGlobal: value.location)
            }
            .onEnded { _ in
                guard dragCoordinator.shouldHandleDragGlobally else { return }
                guard let item = dragCoordinator.sessionItem else {
                    dragCoordinator.cancelDrag()
                    return
                }
                guard let commit = dragCoordinator.completeGlobalDrag() else { return }
                applyGlobalDragCommit(item, commit: commit)
            }
    }

    private var scopePinchGesture: some Gesture {
        // Product spec uses "pinch in" for detail scope and "pinch out" for broader scope.
        MagnifyGesture(minimumScaleDelta: 0.08)
            .onEnded { value in
                if value.magnification > 1 {
                    applyScopeTransition(.pinchIn)
                } else if value.magnification < 1 {
                    applyScopeTransition(.pinchOut)
                }
            }
    }

    private func applyScopeTransition(_ direction: CalendarScopePinchDirection) {
        guard let nextState = CalendarScopeTransition.nextState(
            from: viewModel.scopeTransitionState,
            pinch: direction
        ) else {
            return
        }

        withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
            viewModel.applyScopeTransitionState(nextState)
        }
    }

    // MARK: - Live Activity 자동 시작

    private func checkLiveActivity() async {
        // Live Activity 지원 확인
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let todayItems = await eventKitService.fetchAllItems(for: Date())
        let timedItems = todayItems.filter { $0.startDate != nil && $0.endDate != nil && !$0.isAllDay }

        if timedItems.isEmpty {
            return
        }

        if liveActivityService.isActivityActive {
            liveActivityService.update(events: timedItems)
        } else {
            try? liveActivityService.start(events: timedItems)
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
        // 캐시 무효화하여 즉시 반영
        eventKitService.invalidateMonthCache()
        eventKitService.lastChangeDate = Date()
    }

    private func applyGlobalDragCommit(
        _ item: TicItem,
        commit: DragSessionCommit
    ) {
        do {
            try eventKitService.moveToDate(item, newStart: commit.start, newEnd: commit.end)

            withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
                viewModel.selectedDate = commit.start.startOfDay
                if viewModel.scope != .day {
                    viewModel.scope = .day
                }
            }
        } catch {
            eventKitService.lastChangeDate = Date()
        }
    }
}
