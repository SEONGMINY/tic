import Foundation
import CoreGraphics

enum DragOverlayStyle: String, Equatable {
    case timelineCard
    case calendarPill
}

enum DragOverlayVisualPhase: String, Equatable {
    case inactive
    case anchored
    case lifted
    case floating
    case holding
    case restoring
    case landing
}

struct DragOverlayAnimationTimings: Equatable {
    var liftDurationMs: Int
    var scopeHoldDurationMs: Int
    var pillTransitionDurationMs: Int
    var landingDurationMs: Int

    static let baseline = DragOverlayAnimationTimings(
        liftDurationMs: 140,
        scopeHoldDurationMs: 100,
        pillTransitionDurationMs: 160,
        landingDurationMs: 180
    )
}

struct DragOverlayPresentation: Equatable {
    var style: DragOverlayStyle
    var visualPhase: DragOverlayVisualPhase
    var sourcePlaceholderOpacity: Double
    var showsTitle: Bool
    var showsResizeHandles: Bool
    var showsToolbar: Bool
    var overlayScale: CGFloat
    var overlayOpacity: Double
    var shadowOpacity: Double
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat
    var cornerRadius: CGFloat
    var zIndex: Double
    var pillWidth: CGFloat?
    var pillHeight: CGFloat?

    static let inactive = DragOverlayPresentation(
        style: .timelineCard,
        visualPhase: .inactive,
        sourcePlaceholderOpacity: 0,
        showsTitle: false,
        showsResizeHandles: false,
        showsToolbar: false,
        overlayScale: 1,
        overlayOpacity: 0,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowYOffset: 0,
        cornerRadius: 6,
        zIndex: 0,
        pillWidth: nil,
        pillHeight: nil
    )
}

struct DragOverlayPresentationContext: Equatable {
    var visualPhase: DragOverlayVisualPhase
    var scope: DragSessionScope
    var pillWidth: CGFloat
}

enum DragOverlayPresentationResolver {
    static let defaultPillWidth: CGFloat = 48
    static let defaultPillHeight: CGFloat = 16

    static func resolve(_ context: DragOverlayPresentationContext) -> DragOverlayPresentation {
        guard context.visualPhase != .inactive else {
            return .inactive
        }

        let style = resolvedStyle(for: context)
        let showsTitle = style == .timelineCard
        let sourcePlaceholderOpacity: Double = switch context.visualPhase {
        case .anchored:
            0
        case .lifted:
            0.14
        case .floating:
            style == .timelineCard ? 0.10 : 0.06
        case .holding:
            0.08
        case .restoring:
            0.18
        case .landing:
            0.0
        case .inactive:
            0
        }

        let overlayScale: CGFloat = switch context.visualPhase {
        case .anchored:
            1
        case .lifted:
            1.03
        case .floating:
            style == .timelineCard ? 1.02 : 1
        case .holding:
            1.01
        case .restoring:
            1
        case .landing:
            1
        case .inactive:
            1
        }

        let shadowOpacity: Double = switch context.visualPhase {
        case .anchored:
            0
        case .lifted:
            0.28
        case .floating:
            style == .timelineCard ? 0.22 : 0.16
        case .holding:
            0.18
        case .restoring:
            0.12
        case .landing:
            0.12
        case .inactive:
            0
        }

        let shadowRadius: CGFloat = switch context.visualPhase {
        case .anchored:
            0
        case .lifted:
            10
        case .floating:
            style == .timelineCard ? 8 : 6
        case .holding:
            7
        case .restoring:
            5
        case .landing:
            5
        case .inactive:
            0
        }

        let shadowYOffset: CGFloat = switch context.visualPhase {
        case .lifted, .floating, .holding:
            4
        case .restoring, .landing:
            2
        case .anchored, .inactive:
            0
        }

        return DragOverlayPresentation(
            style: style,
            visualPhase: context.visualPhase,
            sourcePlaceholderOpacity: sourcePlaceholderOpacity,
            showsTitle: showsTitle,
            showsResizeHandles: false,
            showsToolbar: false,
            overlayScale: overlayScale,
            overlayOpacity: 1,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowYOffset: shadowYOffset,
            cornerRadius: style == .timelineCard ? 6 : defaultPillHeight / 2,
            zIndex: 10,
            pillWidth: style == .calendarPill ? max(context.pillWidth, defaultPillWidth) : nil,
            pillHeight: style == .calendarPill ? defaultPillHeight : nil
        )
    }

    private static func resolvedStyle(
        for context: DragOverlayPresentationContext
    ) -> DragOverlayStyle {
        switch context.visualPhase {
        case .inactive, .anchored, .lifted, .holding, .restoring, .landing:
            return .timelineCard
        case .floating:
            return context.scope == .day ? .timelineCard : .calendarPill
        }
    }
}

struct DragCalendarHoverPolicy: Equatable {
    var cellHitInset: CGFloat
    var cellHysteresis: CGFloat

    static func forScope(
        _ scope: DragSessionScope,
        baseHitInset: CGFloat,
        baseHysteresis: CGFloat
    ) -> DragCalendarHoverPolicy {
        switch scope {
        case .month:
            return DragCalendarHoverPolicy(
                cellHitInset: baseHitInset,
                cellHysteresis: baseHysteresis
            )
        case .year:
            return DragCalendarHoverPolicy(
                cellHitInset: baseHitInset + 2,
                cellHysteresis: baseHysteresis + 8
            )
        case .day:
            return DragCalendarHoverPolicy(
                cellHitInset: baseHitInset,
                cellHysteresis: baseHysteresis
            )
        }
    }
}

enum DragCalendarHoverResolver {
    static func activeDate(
        pointerGlobal: CGPoint,
        scope: DragSessionScope,
        dateCellFrames: [DateCellFrame],
        baseHitInset: CGFloat,
        previousActiveDate: Date?,
        baseHysteresis: CGFloat
    ) -> Date? {
        let policy = DragCalendarHoverPolicy.forScope(
            scope,
            baseHitInset: baseHitInset,
            baseHysteresis: baseHysteresis
        )

        if let previousActiveDate,
           let previousCell = dateCellFrames.first(where: { $0.date.isSameDay(as: previousActiveDate) }) {
            let hysteresisRect = DragSessionGeometry.expand(
                previousCell.frameGlobal,
                by: policy.cellHysteresis
            )
            if DragSessionGeometry.pointInRect(pointerGlobal, rect: hysteresisRect) {
                return previousCell.date
            }
        }

        for cell in dateCellFrames {
            let targetRect = DragSessionGeometry.safeInset(
                cell.frameGlobal,
                by: policy.cellHitInset
            )
            if DragSessionGeometry.pointInRect(pointerGlobal, rect: targetRect) {
                return cell.date
            }
        }
        return nil
    }
}
