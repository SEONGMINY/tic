import SwiftUI

struct ContentView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var eventKitService = EventKitService()
    @State private var dayViewModel = DayViewModel()
    @State private var notificationService = NotificationService()
    @State private var eventFormViewModel = EventFormViewModel()
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showEventForm = false

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
                    Text("설정 — Phase 5에서 구현")
                        .presentationDetents([.medium])
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
                    Text("검색 — Phase 5에서 구현")
                }
        }
        .task {
            await eventKitService.requestCalendarAccess()
            await eventKitService.requestReminderAccess()
            eventKitService.startObservingChanges()
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
}
