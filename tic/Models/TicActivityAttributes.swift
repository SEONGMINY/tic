import ActivityKit
import Foundation

struct TicActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var events: [ActivityEvent]  // 오늘의 전체 일정 (최대 10개)
        var currentIndex: Int?       // 현재 진행 중 일정 index
        var nextIndex: Int?          // 다음 일정 index
    }
}

struct ActivityEvent: Codable, Hashable {
    var title: String
    var startDate: Date
    var endDate: Date
    var colorHex: String           // 캘린더 고유 색상 (#RRGGBB)
}
