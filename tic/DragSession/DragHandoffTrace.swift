import Foundation

enum DragHandoffRestoreTraceReason: String, Equatable {
    case timeout
    case cancelled
    case invalidDrop
}

enum DragHandoffTraceEvent: Equatable {
    case dragStart(token: DragTouchClaimToken)
    case rootClaimSuccess(token: DragTouchClaimToken)
    case rootClaimTimeout(token: DragTouchClaimToken)
    case restoreReason(DragHandoffRestoreTraceReason)
    case claimLatencyMs(Int)
}

struct DragHandoffTraceSink {
    private let recordEvent: (DragHandoffTraceEvent) -> Void

    init(recordEvent: @escaping (DragHandoffTraceEvent) -> Void = { _ in }) {
        self.recordEvent = recordEvent
    }

    func record(_ event: DragHandoffTraceEvent) {
        recordEvent(event)
    }

    static let disabled = DragHandoffTraceSink()
}

final class DragHandoffTraceRecorder {
    private(set) var events: [DragHandoffTraceEvent] = []

    lazy var sink: DragHandoffTraceSink = DragHandoffTraceSink { [weak self] event in
        self?.events.append(event)
    }
}
