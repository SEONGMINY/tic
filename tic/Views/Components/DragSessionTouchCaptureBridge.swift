import SwiftUI
import UIKit

final class DragSessionTouchCaptureController {
    fileprivate weak var recognizer: DragSessionTouchCaptureRecognizer?
    fileprivate var onTrackingAttached: ((DragTouchClaimToken) -> Void)?
    fileprivate var onMove: ((DragTouchClaimToken, CGPoint) -> Void)?
    fileprivate var onEnd: ((DragTouchClaimToken) -> Void)?
    fileprivate var onCancel: ((DragTouchClaimToken) -> Void)?

    func requestClaim(
        for token: DragTouchClaimToken,
        near point: CGPoint
    ) {
        recognizer?.requestClaim(for: token, near: point)
    }

    func releaseTracking() {
        recognizer?.releaseActiveTouch()
    }
}

struct DragSessionTouchCaptureBridge: UIViewRepresentable {
    let controller: DragSessionTouchCaptureController
    let onTrackingAttached: (DragTouchClaimToken) -> Void
    let onMove: (DragTouchClaimToken, CGPoint) -> Void
    let onEnd: (DragTouchClaimToken) -> Void
    let onCancel: (DragTouchClaimToken) -> Void

    func makeUIView(context: Context) -> DragSessionTouchCaptureInstallerView {
        let view = DragSessionTouchCaptureInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.controller = controller
        return view
    }

    func updateUIView(_ uiView: DragSessionTouchCaptureInstallerView, context: Context) {
        controller.onTrackingAttached = onTrackingAttached
        controller.onMove = onMove
        controller.onEnd = onEnd
        controller.onCancel = onCancel
        uiView.controller = controller
        uiView.installRecognizerIfNeeded()
    }
}

final class DragSessionTouchCaptureInstallerView: UIView {
    weak var controller: DragSessionTouchCaptureController?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installRecognizerIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installRecognizerIfNeeded()
    }

    func installRecognizerIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let hostView = self.superview else { return }
            if self.controller?.recognizer?.view === hostView {
                return
            }

            let recognizer = DragSessionTouchCaptureRecognizer()
            recognizer.onTrackingAttached = { [weak controller = self.controller] token in
                controller?.onTrackingAttached?(token)
            }
            recognizer.onTrackedTouchMoved = { [weak controller = self.controller] token, point in
                controller?.onMove?(token, point)
            }
            recognizer.onTrackedTouchEnded = { [weak controller = self.controller] token in
                controller?.onEnd?(token)
            }
            recognizer.onTrackedTouchCancelled = { [weak controller = self.controller] token in
                controller?.onCancel?(token)
            }

            hostView.addGestureRecognizer(recognizer)
            self.controller?.recognizer = recognizer
        }
    }
}

final class DragSessionTouchCaptureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTrackingAttached: ((DragTouchClaimToken) -> Void)?
    var onTrackedTouchMoved: ((DragTouchClaimToken, CGPoint) -> Void)?
    var onTrackedTouchEnded: ((DragTouchClaimToken) -> Void)?
    var onTrackedTouchCancelled: ((DragTouchClaimToken) -> Void)?

    private var trackedTouches: [ObjectIdentifier: UITouch] = [:]
    private var activeTouchIdentifier: ObjectIdentifier?
    private var activeClaimToken: DragTouchClaimToken?
    private var pendingClaim: PendingClaim?

    private struct PendingClaim {
        let token: DragTouchClaimToken
        let point: CGPoint
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func requestClaim(
        for token: DragTouchClaimToken,
        near point: CGPoint
    ) {
        activeTouchIdentifier = nil
        activeClaimToken = nil
        pendingClaim = PendingClaim(token: token, point: point)
        resolvePendingClaimIfPossible()
    }

    func releaseActiveTouch() {
        pendingClaim = nil
        activeClaimToken = nil
        activeTouchIdentifier = nil
        trackedTouches.removeAll()

        switch state {
        case .began, .changed:
            state = .cancelled
        case .possible:
            state = .failed
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            trackedTouches[ObjectIdentifier(touch)] = touch
        }
        resolvePendingClaimIfPossible()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let identifier = ObjectIdentifier(touch)
            trackedTouches[identifier] = touch

            if activeTouchIdentifier == nil {
                resolvePendingClaimIfPossible()
            }

            guard identifier == activeTouchIdentifier else { continue }
            if state == .began {
                state = .changed
            }
            guard let token = activeClaimToken else { continue }
            onTrackedTouchMoved?(token, globalLocation(for: touch))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        handleFinishedTouches(
            touches,
            finishState: .ended,
            completion: onTrackedTouchEnded
        )
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        handleFinishedTouches(
            touches,
            finishState: .cancelled,
            completion: onTrackedTouchCancelled
        )
    }

    override func reset() {
        trackedTouches.removeAll()
        activeTouchIdentifier = nil
        activeClaimToken = nil
        pendingClaim = nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private func handleFinishedTouches(
        _ touches: Set<UITouch>,
        finishState: UIGestureRecognizer.State,
        completion: ((DragTouchClaimToken) -> Void)?
    ) {
        var finishedActiveTouch = false

        for touch in touches {
            let identifier = ObjectIdentifier(touch)
            trackedTouches.removeValue(forKey: identifier)
            if identifier == activeTouchIdentifier {
                finishedActiveTouch = true
            }
        }

        if finishedActiveTouch {
            let token = activeClaimToken
            activeTouchIdentifier = nil
            activeClaimToken = nil
            if let token {
                completion?(token)
            }
            state = finishState
            return
        }

        if trackedTouches.isEmpty, let pendingClaim {
            let token = pendingClaim.token
            self.pendingClaim = nil
            completion?(token)
            if state == .possible {
                state = .failed
            }
            return
        }
    }

    private func globalLocation(for touch: UITouch) -> CGPoint {
        if let window = view?.window {
            return touch.location(in: window)
        }
        if let view {
            return touch.location(in: view)
        }
        return .zero
    }

    private func resolvePendingClaimIfPossible() {
        guard activeTouchIdentifier == nil,
              let pendingClaim,
              let trackedTouch = nearestTrackedTouch(to: pendingClaim.point) else {
            return
        }

        activeTouchIdentifier = ObjectIdentifier(trackedTouch)
        activeClaimToken = pendingClaim.token
        self.pendingClaim = nil
        state = .began
        onTrackingAttached?(pendingClaim.token)
        onTrackedTouchMoved?(pendingClaim.token, globalLocation(for: trackedTouch))
    }

    private func nearestTrackedTouch(to point: CGPoint) -> UITouch? {
        trackedTouches.values.min(by: {
            globalLocation(for: $0).distance(to: point) < globalLocation(for: $1).distance(to: point)
        })
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt((dx * dx) + (dy * dy))
    }
}
