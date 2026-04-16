import SwiftUI

struct CalendarDateFramePreferenceKey: PreferenceKey {
    static var defaultValue: [DateCellFrame] = []

    static func reduce(value: inout [DateCellFrame], nextValue: () -> [DateCellFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private struct CalendarDateFrameReporter: ViewModifier {
    let date: Date

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CalendarDateFramePreferenceKey.self,
                    value: [DateCellFrame(date: date, frameGlobal: proxy.frame(in: .global))]
                )
            }
        }
    }
}

extension View {
    func reportCalendarDateFrame(_ date: Date) -> some View {
        modifier(CalendarDateFrameReporter(date: date))
    }
}
