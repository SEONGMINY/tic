import EventKit
import SwiftUI
import SwiftData

struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    var eventKitService: EventKitService
    var notificationService: NotificationService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var searchTask: Task<Void, Never>?
    @State private var showEventForm = false
    @State private var eventFormViewModel = EventFormViewModel()

    var body: some View {
        Group {
            if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                recentSearchesView
            } else if viewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.results.isEmpty {
                ContentUnavailableView("검색 결과 없음", systemImage: "magnifyingglass")
            } else {
                searchResultsView
            }
        }
        .navigationTitle("검색")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.query, prompt: "일정 검색...")
        .onSubmit(of: .search) {
            viewModel.saveHistory(context: modelContext)
            searchTask?.cancel()
            searchTask = Task {
                await viewModel.search(service: eventKitService)
            }
        }
        .onChange(of: viewModel.query) {
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await viewModel.search(service: eventKitService)
            }
        }
        .onAppear {
            viewModel.loadHistory(context: modelContext)
        }
        .sheet(isPresented: $showEventForm) {
            EventFormView(
                viewModel: eventFormViewModel,
                eventKitService: eventKitService,
                notificationService: notificationService,
                onDismiss: { showEventForm = false }
            )
        }
    }

    // MARK: - 최근 검색 기록

    @ViewBuilder
    private var recentSearchesView: some View {
        if viewModel.recentSearches.isEmpty {
            ContentUnavailableView("최근 검색 기록이 없습니다", systemImage: "clock")
        } else {
            List {
                Section("최근 검색") {
                    ForEach(viewModel.recentSearches, id: \.query) { item in
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text(item.query)
                            Spacer()
                            Button {
                                viewModel.deleteHistory(item, context: modelContext)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.query = item.query
                            viewModel.saveHistory(context: modelContext)
                            searchTask?.cancel()
                            searchTask = Task {
                                await viewModel.search(service: eventKitService)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 검색 결과

    private var sortedDateKeys: [Date] {
        viewModel.results.keys.sorted()
    }

    private var searchResultsView: some View {
        List {
            ForEach(sortedDateKeys, id: \.self) { date in
                Section(header: Text(sectionHeader(for: date))) {
                    ForEach(viewModel.results[date] ?? [], id: \.id) { item in
                        resultRow(item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                eventFormViewModel.prepareForEdit(item, service: eventKitService)
                                showEventForm = true
                            }
                    }
                }
            }
        }
    }

    private func resultRow(_ item: TicItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(cgColor: item.calendarColor))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                if let start = item.startDate, item.hasTime {
                    Text(start, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if item.isReminder && !item.hasTime {
                    Text("시간 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(item.calendarTitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func sectionHeader(for date: Date) -> String {
        if date == .distantPast {
            return "날짜 없음"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }
}
