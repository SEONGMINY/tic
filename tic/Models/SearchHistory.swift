import SwiftData
import Foundation

@Model
class SearchHistory {
    var query: String
    var searchedAt: Date

    init(query: String) {
        self.query = query
        self.searchedAt = .now
    }
}
