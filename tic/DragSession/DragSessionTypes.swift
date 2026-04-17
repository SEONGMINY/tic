import Foundation
import CoreGraphics

enum DragSessionScope: String, CaseIterable, Codable {
    case day
    case month
    case year
}

enum DragSessionState: String, Equatable {
    case idle
    case pressing
    case dragReady
    case draggingTimeline
    case draggingCalendar
    case restoring
}

enum DragSessionOutcome: String, Equatable {
    case none
    case dropped
    case cancelled
}

enum DragSessionInvalidReason: String, Equatable {
    case falseStartPreLongPress
    case invalidDrop
    case cancelledByEvent
}

enum DragInvalidDropPolicy: String, Equatable {
    case restore
}

struct DragSessionParams: Equatable {
    var longPressMinMs: Int
    var pressSlopPt: CGFloat
    var dragStartMinDistancePt: CGFloat
    var hoverActivationMs: Int
    var hoverExitMs: Int
    var cellHitInsetPt: CGFloat
    var cellHysteresisPt: CGFloat
    var timelineDropInsetPt: CGFloat
    var minuteSnapStep: Int
    var minimumDurationMinute: Int
    var restoreAnimationMs: Int
    var reanchorBlendMs: Int
    var invalidDropPolicy: DragInvalidDropPolicy

    static let baseline = DragSessionParams(
        longPressMinMs: 500,
        pressSlopPt: 10,
        dragStartMinDistancePt: 6,
        hoverActivationMs: 120,
        hoverExitMs: 80,
        cellHitInsetPt: 6,
        cellHysteresisPt: 12,
        timelineDropInsetPt: 8,
        minuteSnapStep: 15,
        minimumDurationMinute: 30,
        restoreAnimationMs: 220,
        reanchorBlendMs: 140,
        invalidDropPolicy: .restore
    )
}

struct DragTimelineLayout: Equatable {
    var frameGlobal: CGRect
    var scrollOffsetY: CGFloat
    var hourHeight: CGFloat

    init(
        frameGlobal: CGRect,
        scrollOffsetY: CGFloat = 0,
        hourHeight: CGFloat = 60
    ) {
        self.frameGlobal = frameGlobal
        self.scrollOffsetY = scrollOffsetY
        self.hourHeight = hourHeight
    }
}

struct DateCellFrame: Equatable {
    var date: Date
    var frameGlobal: CGRect

    init(date: Date, frameGlobal: CGRect) {
        self.date = date.startOfDay
        self.frameGlobal = frameGlobal
    }
}

struct DragSessionSource: Equatable {
    var itemId: String
    var sourceDate: Date
    var sourceStartMinute: Int
    var sourceEndMinute: Int
    var originalFrameGlobal: CGRect

    init(
        itemId: String,
        sourceDate: Date,
        sourceStartMinute: Int,
        sourceEndMinute: Int,
        originalFrameGlobal: CGRect
    ) {
        self.itemId = itemId
        self.sourceDate = sourceDate.startOfDay
        self.sourceStartMinute = sourceStartMinute
        self.sourceEndMinute = sourceEndMinute
        self.originalFrameGlobal = originalFrameGlobal
    }

    var durationMinute: Int {
        sourceEndMinute - sourceStartMinute
    }
}

struct DragDropResult: Equatable {
    var date: Date
    var startMinute: Int
    var endMinute: Int

    init(date: Date, startMinute: Int, endMinute: Int) {
        self.date = date.startOfDay
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

enum DragOwnershipHandoffPhase: String, Equatable {
    case idle
    case localPreview
    case rootClaimPending
    case rootClaimAcquired
    case landing
    case restoring
}

struct DragOwnershipHandoffState: Equatable {
    var phase: DragOwnershipHandoffPhase
    var token: DragTouchClaimToken?
    var owner: DragTouchClaimOwner
    var restoreReason: DragTouchClaimRestoreReason?
    var claimSnapshot: DragTouchClaimSnapshot?

    static let idle = Self(
        phase: .idle,
        token: nil,
        owner: .none,
        restoreReason: nil,
        claimSnapshot: nil
    )

    var isLocalPreviewActive: Bool {
        phase == .localPreview || phase == .rootClaimPending
    }

    var isRootClaimPending: Bool {
        phase == .rootClaimPending
    }

    var isRootClaimAcquired: Bool {
        switch phase {
        case .rootClaimAcquired:
            return true
        case .landing, .restoring:
            return owner == .root
        case .idle, .localPreview, .rootClaimPending:
            return false
        }
    }

    var showsPlaceholder: Bool {
        isRootClaimAcquired
    }

    var allowsCalendarHover: Bool {
        phase == .rootClaimAcquired || (phase == .landing && owner == .root)
    }

    var canHandleLocalDayDrop: Bool {
        phase == .localPreview || phase == .rootClaimPending
    }

    var canHandleGlobalDrag: Bool {
        phase == .rootClaimAcquired
    }

    var dropOwner: DragDropOwner {
        isRootClaimAcquired ? .rootCoordinator : .localDayTimeline
    }
}

struct DragSessionSnapshot: Equatable {
    var params: DragSessionParams
    var state: DragSessionState
    var outcome: DragSessionOutcome
    var currentScope: DragSessionScope
    var source: DragSessionSource?
    var pointerGlobal: CGPoint?
    var pressStartPointGlobal: CGPoint?
    var anchorToBlockOrigin: CGPoint?
    var overlayFrameGlobal: CGRect?
    var restoreTargetFrameGlobal: CGRect?
    var dateCandidate: Date?
    var minuteCandidate: Int?
    var activeDate: Date?
    var dragStarted: Bool
    var dragStartTimestampMs: Int?
    var invalidReason: DragSessionInvalidReason?
    var finalDropResult: DragDropResult?

    init(
        params: DragSessionParams = .baseline,
        state: DragSessionState = .idle,
        outcome: DragSessionOutcome = .none,
        currentScope: DragSessionScope = .day,
        source: DragSessionSource? = nil,
        pointerGlobal: CGPoint? = nil,
        pressStartPointGlobal: CGPoint? = nil,
        anchorToBlockOrigin: CGPoint? = nil,
        overlayFrameGlobal: CGRect? = nil,
        restoreTargetFrameGlobal: CGRect? = nil,
        dateCandidate: Date? = nil,
        minuteCandidate: Int? = nil,
        activeDate: Date? = nil,
        dragStarted: Bool = false,
        dragStartTimestampMs: Int? = nil,
        invalidReason: DragSessionInvalidReason? = nil,
        finalDropResult: DragDropResult? = nil
    ) {
        self.params = params
        self.state = state
        self.outcome = outcome
        self.currentScope = currentScope
        self.source = source
        self.pointerGlobal = pointerGlobal
        self.pressStartPointGlobal = pressStartPointGlobal
        self.anchorToBlockOrigin = anchorToBlockOrigin
        self.overlayFrameGlobal = overlayFrameGlobal
        self.restoreTargetFrameGlobal = restoreTargetFrameGlobal
        self.dateCandidate = dateCandidate?.startOfDay
        self.minuteCandidate = minuteCandidate
        self.activeDate = activeDate?.startOfDay
        self.dragStarted = dragStarted
        self.dragStartTimestampMs = dragStartTimestampMs
        self.invalidReason = invalidReason
        self.finalDropResult = finalDropResult
    }

    var durationMinute: Int? {
        source?.durationMinute
    }

    var placeholderVisible: Bool {
        source != nil && state != .idle
    }

    var dropCandidateDate: Date? {
        switch currentScope {
        case .day:
            return dateCandidate ?? source?.sourceDate
        case .month, .year:
            return activeDate ?? dateCandidate
        }
    }

    var droppable: Bool {
        guard let durationMinute else { return false }
        guard state == .draggingTimeline || state == .draggingCalendar else { return false }
        return DragSessionGeometry.buildFinalDropResult(
            dateCandidate: dropCandidateDate,
            minuteCandidate: minuteCandidate,
            durationMinute: durationMinute,
            minimumDurationMinute: params.minimumDurationMinute
        ) != nil
    }
}
