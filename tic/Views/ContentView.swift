import SwiftUI
import SwiftData
import ActivityKit
import UIKit

struct ContentView: View {
    @Query private var calendarSelections: [CalendarSelection]
    @State private var viewModel = CalendarViewModel()
    @State private var eventKitService = EventKitService()
    @State private var dayViewModel = DayViewModel()
    @State private var notificationService = NotificationService()
    @State private var eventFormViewModel = EventFormViewModel()
    @State private var liveActivityService = LiveActivityService()
    @State private var dragCoordinator = CalendarDragCoordinator()
    @State private var rootTouchCapture = DragSessionTouchCaptureController()
    @State private var rootClaimTimeoutWorkItem: DispatchWorkItem?
    @State private var dayEdgeHoverWorkItem: DispatchWorkItem?
    @State private var dayEdgeHoverDirection: DragDayEdgeHoverDirection?
    @State private var dayEdgeHoverToken: DragTouchClaimToken?
    @State private var latestCapturedPointerGlobal: CGPoint?
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showEventForm = false
    @Environment(\.scenePhase) private var scenePhase
    private let liveActivityTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let rootClaimTimeoutSeconds = 2.0 / 60.0
    private let dayEdgeHoverInset: CGFloat = 24
    private let dayEdgeHoverDwellSeconds = 0.12

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
        .background {
            DragSessionTouchCaptureBridge(
                controller: rootTouchCapture,
                onTrackingAttached: { token in
                    cancelRootClaimTimeout()
                    dragCoordinator.attachTouchTrackingRelay(for: token)
                },
                onMove: { token, point in
                    handleDragMoveFromRootCapture(for: token, pointerGlobal: point)
                },
                onEnd: { token in
                    handleCapturedDragTermination(
                        for: token,
                        termination: .ended,
                        source: .root
                    )
                },
                onCancel: { token in
                    handleCapturedDragTermination(
                        for: token,
                        termination: .cancelled,
                        source: .root
                    )
                }
            )
        }
        .overlay(alignment: .topLeading) {
            if let overlayItem = dragCoordinator.rootOverlayItem,
               let overlayFrame = dragCoordinator.rootOverlayFrameLocal {
                DragSessionOverlayBlock(
                    item: overlayItem,
                    frame: overlayFrame,
                    presentation: dragCoordinator.overlayPresentation
                )
                    .zIndex(dragCoordinator.overlayPresentation.zIndex)
            }
        }
        .overlay(alignment: .topLeading) {
            if DragDebugLog.isEnabled {
                Text(dragDebugSummary)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .background(.black.opacity(0.72))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .accessibilityIdentifier("drag-debug-overlay")
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
            if newScope != .day {
                cancelDayEdgeHover()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // 포그라운드 복귀 시 Live Activity 체크
                Task { await checkLiveActivity() }
            } else if dragCoordinator.hasActiveSession {
                cancelRootClaimTimeout()
                cancelDayEdgeHover()
                dragCoordinator.cancelDrag()
                rootTouchCapture.releaseTracking()
            }
        }
        .onChange(of: dragCoordinator.sessionTerminationCount) { _, _ in
            cancelRootClaimTimeout()
            cancelDayEdgeHover()
            rootTouchCapture.releaseTracking()
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

    private var dragDebugSummary: String {
        let minute = dragCoordinator.snapshot.minuteCandidate.map(String.init) ?? "nil"
        let date = dragCoordinator.snapshot.dropCandidateDate?.formatted(date: .abbreviated, time: .omitted) ?? "nil"
        let termination = dragCoordinator.lastSessionTermination.map { String(describing: $0) } ?? "nil"
        let pointer = dragCoordinator.debugPointerGlobal.map(debugPointString) ?? "nil"
        let timelineFrame = dragCoordinator.timelineFrameGlobal.map(debugRectString) ?? "nil"
        let dropZone = dragCoordinator.debugTimelineDropZoneGlobal.map(debugRectString) ?? "nil"
        let insideDropZone = dragCoordinator.debugTimelinePointerInsideDropZone.map {
            $0 ? "true" : "false"
        } ?? "nil"
        return [
            "phase=\(dragCoordinator.handoffState.phase.rawValue)",
            "owner=\(dragCoordinator.currentHandoffOwner.rawValue)",
            "state=\(dragCoordinator.snapshot.state.rawValue)",
            "scope=\(dragCoordinator.snapshot.currentScope.rawValue)",
            "timeline=\(dragCoordinator.timelineFrameGlobal != nil)",
            "frame=\(timelineFrame)",
            "zone=\(dropZone)",
            "pointer=\(pointer)",
            "inside=\(insideDropZone)",
            "minute=\(minute)",
            "date=\(date)",
            "active=\(dragCoordinator.hasActiveSession)",
            "term=\(termination)"
        ].joined(separator: "\n")
    }

    private func debugPointString(_ point: CGPoint) -> String {
        "\(debugNumberString(point.x)),\(debugNumberString(point.y))"
    }

    private func debugRectString(_ rect: CGRect) -> String {
        [
            debugNumberString(rect.minX),
            debugNumberString(rect.minY),
            debugNumberString(rect.width),
            debugNumberString(rect.height)
        ].joined(separator: ",")
    }

    private func debugNumberString(_ value: CGFloat) -> String {
        let doubleValue = Double(value)
        guard doubleValue.isFinite else {
            if doubleValue.isNaN {
                return "nan"
            }
            return doubleValue.sign == .minus ? "-inf" : "inf"
        }
        return String(Int(doubleValue.rounded()))
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
                },
                onBeginMoveDrag: { item, sourceFrameGlobal, startPointerGlobal, currentPointerGlobal in
                    beginCapturedMoveDrag(
                        item: item,
                        sourceFrameGlobal: sourceFrameGlobal,
                        startPointerGlobal: startPointerGlobal,
                        currentPointerGlobal: currentPointerGlobal
                    )
                },
                onMoveDragChanged: { pointerGlobal in
                    handleLocalDayDragChanged(pointerGlobal: pointerGlobal)
                },
                onMoveDragEnded: { pointerGlobal in
                    handleLocalDayDragEnded(pointerGlobal: pointerGlobal)
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 1.02)))
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
        DragDebugLog.log(
            "applyGlobalDragCommit item=\(item.id) start=\(commit.start) end=\(commit.end)"
        )
        do {
            try eventKitService.moveToDate(item, newStart: commit.start, newEnd: commit.end)
            dayViewModel.registerPendingTimedItemMove(
                item: item,
                newStart: commit.start,
                newEnd: commit.end
            )
            let nextState = CalendarScopeTransition.stateAfterGlobalDrop(commit: commit)

            withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
                viewModel.applyScopeTransitionState(nextState)
            }
        } catch {
            dayViewModel.pendingTimedItemMove = nil
            eventKitService.lastChangeDate = Date()
        }
    }

    private func beginCapturedMoveDrag(
        item: TicItem,
        sourceFrameGlobal: CGRect,
        startPointerGlobal: CGPoint,
        currentPointerGlobal: CGPoint
    ) {
        if dragCoordinator.hasActiveSession {
            DragDebugLog.log("beginCapturedMoveDrag ignored existing session")
            return
        }

        cancelDayEdgeHover()

        guard let token = dragCoordinator.beginDayDrag(
            item: item,
            sourceFrameGlobal: sourceFrameGlobal,
            pointerGlobal: startPointerGlobal
        ) else {
            DragDebugLog.log("beginCapturedMoveDrag failed to acquire token")
            return
        }

        DragDebugLog.log(
            "beginCapturedMoveDrag token=\(token.rawValue) start=\(startPointerGlobal.debugDescription) current=\(currentPointerGlobal.debugDescription)"
        )

        scheduleRootClaimTimeout(for: token)
        rootTouchCapture.requestClaim(for: token, near: currentPointerGlobal)

        if dragCoordinator.currentHandoffOwner == .localPreview {
            dragCoordinator.updateActiveDrag(pointerGlobal: currentPointerGlobal)
            DragDebugLog.log(
                "beginCapturedMoveDrag localPreview updated scope=\(String(describing: dragCoordinator.snapshot.currentScope)) minute=\(String(describing: dragCoordinator.snapshot.minuteCandidate))"
            )
        }
    }

    private func handleDragMoveFromRootCapture(
        for token: DragTouchClaimToken,
        pointerGlobal: CGPoint
    ) {
        latestCapturedPointerGlobal = pointerGlobal
        DragDebugLog.log(
            "handleDragMoveFromRootCapture token=\(token.rawValue) point=\(pointerGlobal.debugDescription) owner=\(dragCoordinator.currentHandoffOwner.rawValue) scope=\(String(describing: dragCoordinator.snapshot.currentScope))"
        )
        dragCoordinator.updateRelayedTouchMove(for: token, pointerGlobal: pointerGlobal)
        if dragCoordinator.shouldPromoteRelayedTouchToRootClaim(for: token) {
            cancelRootClaimTimeout()
            _ = dragCoordinator.applyRootClaimSuccess(for: token)
            DragDebugLog.log("handleDragMoveFromRootCapture promoted token=\(token.rawValue)")
        }
        updateDayEdgeHoverTracking(for: token, pointerGlobal: pointerGlobal)
    }

    private func handleLocalDayDragChanged(pointerGlobal: CGPoint) {
        latestCapturedPointerGlobal = pointerGlobal
        guard dragCoordinator.hasActiveSession,
              dragCoordinator.currentHandoffOwner == .localPreview else {
            DragDebugLog.log(
                "handleLocalDayDragChanged ignored point=\(pointerGlobal.debugDescription) hasSession=\(dragCoordinator.hasActiveSession) owner=\(dragCoordinator.currentHandoffOwner.rawValue)"
            )
            return
        }

        dragCoordinator.updateActiveDrag(pointerGlobal: pointerGlobal)
        DragDebugLog.log(
            "handleLocalDayDragChanged point=\(pointerGlobal.debugDescription) minute=\(String(describing: dragCoordinator.snapshot.minuteCandidate)) date=\(String(describing: dragCoordinator.snapshot.dropCandidateDate)) state=\(String(describing: dragCoordinator.snapshot.state))"
        )

        if let token = dragCoordinator.currentHandoffToken {
            updateDayEdgeHoverTracking(for: token, pointerGlobal: pointerGlobal)
        }
    }

    private func handleLocalDayDragEnded(pointerGlobal: CGPoint) {
        latestCapturedPointerGlobal = pointerGlobal
        DragDebugLog.log(
            "handleLocalDayDragEnded point=\(pointerGlobal.debugDescription) owner=\(dragCoordinator.currentHandoffOwner.rawValue) scope=\(String(describing: dragCoordinator.snapshot.currentScope))"
        )
        guard dragCoordinator.hasActiveSession,
              DayDragTerminationPolicy.shouldAcceptLocalDayTermination(
                hasActiveSession: dragCoordinator.hasActiveSession,
                scope: dragCoordinator.snapshot.currentScope
              ) else {
            return
        }

        if dragCoordinator.isGestureSessionActive {
            if dragCoordinator.shouldHandleDragGlobally {
                dragCoordinator.updateGlobalDrag(pointerGlobal: pointerGlobal)
            } else {
                dragCoordinator.updateActiveDrag(pointerGlobal: pointerGlobal)
            }
        }

        guard let token = dragCoordinator.currentHandoffToken else { return }
        handleCapturedDragTermination(
            for: token,
            termination: .ended,
            source: .local
        )
    }

    private func handleCapturedDragTermination(
        for token: DragTouchClaimToken,
        termination: CapturedDragTermination,
        source: DragTerminationSource
    ) {
        DragDebugLog.log(
            "handleCapturedDragTermination token=\(token.rawValue) termination=\(String(describing: termination)) source=\(String(describing: source)) owner=\(dragCoordinator.currentHandoffOwner.rawValue) rootClaim=\(dragCoordinator.handoffState.isRootClaimAcquired) minute=\(String(describing: dragCoordinator.snapshot.minuteCandidate)) date=\(String(describing: dragCoordinator.snapshot.dropCandidateDate))"
        )
        guard dragCoordinator.currentHandoffToken == token else { return }
        guard DayDragTerminationPolicy.shouldHandleTermination(
            source: source,
            termination: termination,
            scope: dragCoordinator.snapshot.currentScope
            ,
            isRootClaimAcquired: dragCoordinator.handoffState.isRootClaimAcquired
        ) else {
            return
        }

        cancelRootClaimTimeout()
        cancelDayEdgeHover()

        guard let item = dragCoordinator.sessionItem else {
            dragCoordinator.cancelDrag()
            return
        }

        if termination == .cancelled {
            guard dragCoordinator.shouldTreatCapturedTouchCancellationAsDrop(
                sceneIsActive: scenePhase == .active
            ) else {
                DragDebugLog.log("handleCapturedDragTermination cancelling token=\(token.rawValue)")
                _ = dragCoordinator.applyRootClaimCancellation(for: token)
                return
            }

            guard let commit = dragCoordinator.completeGlobalDrag() else { return }
            applyGlobalDragCommit(item, commit: commit)
            return
        }

        let commit: DragSessionCommit?
        if dragCoordinator.handoffState.isRootClaimAcquired {
            commit = dragCoordinator.completeGlobalDrag()
        } else if dragCoordinator.shouldHandleDropLocally {
            commit = dragCoordinator.completeLocalDrag()
        } else {
            DragDebugLog.log("handleCapturedDragTermination no local/global drop path token=\(token.rawValue)")
            _ = dragCoordinator.applyRootClaimCancellation(for: token)
            return
        }

        DragDebugLog.log("handleCapturedDragTermination commit=\(String(describing: commit))")
        guard let commit else { return }
        applyGlobalDragCommit(item, commit: commit)
    }

    private func updateDayEdgeHoverTracking(
        for token: DragTouchClaimToken,
        pointerGlobal: CGPoint
    ) {
        guard dragCoordinator.currentHandoffToken == token,
              dragCoordinator.isGestureSessionActive,
              dragCoordinator.snapshot.currentScope == .day,
              let timelineFrame = dragCoordinator.timelineFrameGlobal,
              let direction = DragDayEdgeHoverResolver.direction(
                pointerGlobal: pointerGlobal,
                timelineFrameGlobal: timelineFrame,
                edgeInset: dayEdgeHoverInset
              ) else {
            cancelDayEdgeHover()
            return
        }

        if dayEdgeHoverToken == token,
           dayEdgeHoverDirection == direction,
           dayEdgeHoverWorkItem != nil {
            return
        }

        scheduleDayEdgeHover(for: token, direction: direction)
    }

    private func scheduleDayEdgeHover(
        for token: DragTouchClaimToken,
        direction: DragDayEdgeHoverDirection
    ) {
        cancelDayEdgeHover()
        dayEdgeHoverToken = token
        dayEdgeHoverDirection = direction

        let workItem = DispatchWorkItem { [token, direction] in
            dayEdgeHoverWorkItem = nil
            guard dragCoordinator.currentHandoffToken == token,
                  dragCoordinator.isGestureSessionActive,
                  dragCoordinator.snapshot.currentScope == .day,
                  scenePhase == .active else {
                cancelDayEdgeHover()
                return
            }

            guard dragCoordinator.promotePendingTouchRelayToRootClaim(for: token) else {
                cancelDayEdgeHover()
                return
            }

            let nextDate = viewModel.selectedDate.adding(days: direction.dayDelta)
            guard nextDate.isSameDay(as: viewModel.selectedDate) == false else {
                cancelDayEdgeHover()
                return
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                viewModel.selectedDate = nextDate
            }
            dragCoordinator.updateVisibleDay(nextDate)

            if let latestCapturedPointerGlobal {
                dragCoordinator.updateGlobalDrag(pointerGlobal: latestCapturedPointerGlobal)
                updateDayEdgeHoverTracking(for: token, pointerGlobal: latestCapturedPointerGlobal)
            }
        }

        dayEdgeHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + dayEdgeHoverDwellSeconds,
            execute: workItem
        )
    }

    private func cancelDayEdgeHover() {
        dayEdgeHoverWorkItem?.cancel()
        dayEdgeHoverWorkItem = nil
        dayEdgeHoverDirection = nil
        dayEdgeHoverToken = nil
    }

    private func scheduleRootClaimTimeout(for token: DragTouchClaimToken) {
        cancelRootClaimTimeout()

        let workItem = DispatchWorkItem { [token] in
            guard dragCoordinator.currentHandoffToken == token else { return }
            let result = dragCoordinator.expirePendingRootClaimIfNeeded()
            DragDebugLog.log("rootClaimTimeout token=\(token.rawValue) result=\(String(describing: result))")
            if result == .applied {
                rootTouchCapture.releaseTracking()
            }
        }

        rootClaimTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + rootClaimTimeoutSeconds,
            execute: workItem
        )
    }

    private func cancelRootClaimTimeout() {
        rootClaimTimeoutWorkItem?.cancel()
        rootClaimTimeoutWorkItem = nil
    }
}

enum CapturedDragTermination {
    case ended
    case cancelled
}

enum DragTerminationSource {
    case local
    case root
}

enum DayDragTerminationPolicy {
    static func shouldAcceptLocalDayTermination(
        hasActiveSession: Bool,
        scope: DragSessionScope
    ) -> Bool {
        hasActiveSession && scope == .day
    }

    static func shouldHandleTermination(
        source: DragTerminationSource,
        termination: CapturedDragTermination,
        scope: DragSessionScope,
        isRootClaimAcquired: Bool
    ) -> Bool {
        if source == .root &&
            termination == .cancelled &&
            scope == .day &&
            isRootClaimAcquired == false {
            return false
        }
        return true
    }
}
