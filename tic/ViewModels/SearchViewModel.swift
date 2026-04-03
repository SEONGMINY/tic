import SwiftData
import Foundation

@Observable
class SearchViewModel {
    var query: String = ""
    var results: [Date: [TicItem]] = [:]
    var isSearching: Bool = false
    var recentSearches: [SearchHistory] = []

    // MARK: - 검색

    func search(service: EventKitService) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = [:]
            isSearching = false
            return
        }

        isSearching = true

        let now = Date()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: -1, to: now)!
        let end = calendar.date(byAdding: .year, value: 1, to: now)!

        let events = service.fetchEvents(from: start, to: end)
        let reminders = await service.fetchReminders(from: start, to: end)
        let allItems = events + reminders

        let lowercasedQuery = trimmed.lowercased()
        let filtered = allItems.filter { $0.title.lowercased().contains(lowercasedQuery) }

        var grouped: [Date: [TicItem]] = [:]
        for item in filtered {
            let key: Date
            if let startDate = item.startDate {
                key = startDate.startOfDay
            } else {
                key = Date.distantPast
            }
            grouped[key, default: []].append(item)
        }

        // 각 그룹 내 시간순 정렬
        for key in grouped.keys {
            grouped[key]?.sort { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        }

        results = grouped
        isSearching = false
    }

    // MARK: - SearchHistory CRUD

    func loadHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<SearchHistory>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        recentSearches = (try? context.fetch(descriptor))?.prefix(20).map { $0 } ?? []
    }

    func saveHistory(context: ModelContext) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // 중복 제거: 같은 query면 searchedAt만 업데이트
        let predicate = #Predicate<SearchHistory> { $0.query == trimmed }
        let descriptor = FetchDescriptor<SearchHistory>(predicate: predicate)
        if let existing = try? context.fetch(descriptor).first {
            existing.searchedAt = .now
        } else {
            context.insert(SearchHistory(query: trimmed))
        }

        try? context.save()
        loadHistory(context: context)
    }

    func deleteHistory(_ item: SearchHistory, context: ModelContext) {
        context.delete(item)
        try? context.save()
        loadHistory(context: context)
    }
}
