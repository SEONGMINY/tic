import Foundation

struct WidgetEventItem: Codable {
    let id: String
    let title: String
    let startDate: Date?
    let endDate: Date?
    let isReminder: Bool
    let isCompleted: Bool
    let calendarColorHex: String
    let isAllDay: Bool
}

struct WidgetCache {
    static let suiteName = "group.com.miny.tic"
    static let cacheKey = "widgetEventCache"

    static func save(events: [WidgetEventItem]) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    static func load() -> [WidgetEventItem] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: cacheKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WidgetEventItem].self, from: data)) ?? []
    }
}
