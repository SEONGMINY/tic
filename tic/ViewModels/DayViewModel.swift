import SwiftUI

struct LayoutAttributes {
    let widthFraction: CGFloat
    let xOffset: CGFloat
    let column: Int
    let totalColumns: Int
}

struct PendingTimedItemMove {
    let itemId: String
    let item: TicItem
    let start: Date
    let end: Date

    var targetDate: Date {
        start.startOfDay
    }

    func updatedItem() -> TicItem {
        item.updatingDates(
            startDate: start,
            endDate: end
        )
    }
}

@Observable
class DayViewModel {
    var items: [TicItem] = []
    var timedItems: [TicItem] = []
    var allDayItems: [TicItem] = []
    var timelessReminders: [TicItem] = []
    var nextAction: TicItem?
    var loadedDate: Date?
    var pendingTimedItemMove: PendingTimedItemMove?

    private var requestedDate: Date?

    func loadItems(for date: Date, service: EventKitService) async {
        let targetDate = date.startOfDay
        requestedDate = targetDate
        if loadedDate?.isSameDay(as: targetDate) != true {
            loadedDate = nil
        }

        let all = await service.fetchAllItems(for: targetDate)
        guard requestedDate?.isSameDay(as: targetDate) == true else {
            return
        }

        items = all

        timedItems = all.filter { item in
            !item.isAllDay && item.hasTime && item.startDate != nil
        }
        allDayItems = all.filter { $0.isAllDay }
        timelessReminders = all.filter { $0.isReminder && !$0.hasTime }
        loadedDate = targetDate

        resolvePendingTimedItemMove()
        computeNextAction(for: targetDate)
    }

    func registerPendingTimedItemMove(
        item: TicItem,
        newStart: Date,
        newEnd: Date
    ) {
        pendingTimedItemMove = PendingTimedItemMove(
            itemId: item.id,
            item: item,
            start: newStart,
            end: newEnd
        )
    }

    func projectedTimedItems(for visibleDate: Date) -> [TicItem] {
        var projected = timedItems.filter { item in
            item.id != pendingTimedItemMove?.itemId
        }

        if let pendingTimedItemMove,
           visibleDate.isSameDay(as: pendingTimedItemMove.targetDate) {
            projected.append(pendingTimedItemMove.updatedItem())
        }

        return projected.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    func computeNextAction(for date: Date) {
        guard date.isToday else {
            nextAction = nil
            return
        }
        let now = Date()
        nextAction = timedItems
            .filter { item in
                guard let start = item.startDate else { return false }
                return start > now
            }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .first
    }

    func computeLayout(containerWidth: CGFloat) -> [String: LayoutAttributes] {
        computeLayout(for: timedItems, containerWidth: containerWidth)
    }

    func computeLayout(for items: [TicItem], containerWidth: CGFloat) -> [String: LayoutAttributes] {
        guard !items.isEmpty else { return [:] }

        let sorted = items.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

        // Group into collision clusters
        var clusters: [[TicItem]] = []
        var currentCluster: [TicItem] = []
        var clusterEnd: Date = .distantPast

        for item in sorted {
            guard let start = item.startDate, let end = item.endDate else { continue }
            if start < clusterEnd {
                // overlaps with current cluster
                currentCluster.append(item)
                clusterEnd = max(clusterEnd, end)
            } else {
                if !currentCluster.isEmpty {
                    clusters.append(currentCluster)
                }
                currentCluster = [item]
                clusterEnd = end
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        // Assign columns within each cluster
        var result: [String: LayoutAttributes] = [:]

        for cluster in clusters {
            var columnEnds: [Date] = [] // tracks end time for each column

            for item in cluster {
                guard let start = item.startDate else { continue }

                // Find first available column
                var assignedColumn = -1
                for (col, colEnd) in columnEnds.enumerated() {
                    if start >= colEnd {
                        assignedColumn = col
                        columnEnds[col] = item.endDate ?? start
                        break
                    }
                }
                if assignedColumn == -1 {
                    assignedColumn = columnEnds.count
                    columnEnds.append(item.endDate ?? start)
                }

                // Temporarily store column index
                result[item.id] = LayoutAttributes(
                    widthFraction: 0,
                    xOffset: 0,
                    column: assignedColumn,
                    totalColumns: 0
                )
            }

            // Now set width/offset based on total columns in cluster
            let totalColumns = columnEnds.count
            for item in cluster {
                guard let attrs = result[item.id] else { continue }
                let fraction = 1.0 / CGFloat(totalColumns)
                let offset = CGFloat(attrs.column) * fraction
                result[item.id] = LayoutAttributes(
                    widthFraction: fraction,
                    xOffset: offset,
                    column: attrs.column,
                    totalColumns: totalColumns
                )
            }
        }

        return result
    }

    private func resolvePendingTimedItemMove() {
        guard let pendingTimedItemMove else { return }
        guard loadedDate?.isSameDay(as: pendingTimedItemMove.targetDate) == true else {
            return
        }

        guard let updatedItem = timedItems.first(where: { $0.id == pendingTimedItemMove.itemId }) else {
            return
        }

        if updatedItem.startDate == pendingTimedItemMove.start &&
            updatedItem.endDate == pendingTimedItemMove.end {
            self.pendingTimedItemMove = nil
        }
    }
}
