import SwiftUI
import UIKit

final class DragSessionTouchCaptureController {
    fileprivate weak var recognizer: DragSessionTouchCaptureRecognizer?
    fileprivate var onMove: ((CGPoint) -> Void)?
    fileprivate var onEnd: (() -> Void)?
    fileprivate var onCancel: (() -> Void)?

    @discardableResult
    func captureTouch(near point: CGPoint) -> Bool {
        recognizer?.captureTouch(near: point) == true
    }

    func releaseTracking() {
        recognizer?.releaseActiveTouch()
    }
}

struct DragSessionTouchCaptureBridge: UIViewRepresentable {
    let controller: DragSessionTouchCaptureController
    let onMove: (CGPoint) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> DragSessionTouchCaptureInstallerView {
        let view = DragSessionTouchCaptureInstallerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.controller = controller
        return view
    }

    func updateUIView(_ uiView: DragSessionTouchCaptureInstallerView, context: Context) {
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
            recognizer.onTrackedTouchMoved = { [weak controller = self.controller] point in
                controller?.onMove?(point)
            }
            recognizer.onTrackedTouchEnded = { [weak controller = self.controller] in
                controller?.onEnd?()
            }
            recognizer.onTrackedTouchCancelled = { [weak controller = self.controller] in
                controller?.onCancel?()
            }

            hostView.addGestureRecognizer(recognizer)
            self.controller?.recognizer = recognizer
        }
    }
}

final class DragSessionTouchCaptureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTrackedTouchMoved: ((CGPoint) -> Void)?
    var onTrackedTouchEnded: (() -> Void)?
    var onTrackedTouchCancelled: (() -> Void)?

    private var trackedTouches: [ObjectIdentifier: UITouch] = [:]
    private var activeTouchIdentifier: ObjectIdentifier?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func captureTouch(near point: CGPoint) -> Bool {
        guard activeTouchIdentifier == nil else { return true }
        guard let trackedTouch = trackedTouches.values.min(by: {
            globalLocation(for: $0).distance(to: point) < globalLocation(for: $1).distance(to: point)
        }) else {
            return false
        }

        activeTouchIdentifier = ObjectIdentifier(trackedTouch)
        state = .began
        onTrackedTouchMoved?(globalLocation(for: trackedTouch))
        return true
    }

    func releaseActiveTouch() {
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
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            let identifier = ObjectIdentifier(touch)
            trackedTouches[identifier] = touch

            guard identifier == activeTouchIdentifier else { continue }
            if state == .began {
                state = .changed
            }
            onTrackedTouchMoved?(globalLocation(for: touch))
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
        completion: (() -> Void)?
    ) {
        var finishedActiveTouch = false

        for touch in touches {
            let identifier = ObjectIdentifier(touch)
            trackedTouches.removeValue(forKey: identifier)
            if identifier == activeTouchIdentifier {
                finishedActiveTouch = true
            }
        }

        guard finishedActiveTouch else {
            if trackedTouches.isEmpty && state == .possible {
                state = .failed
            }
            return
        }

        activeTouchIdentifier = nil
        completion?()
        state = finishState
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
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt((dx * dx) + (dy * dy))
    }
}
