import XCTest
@testable import tic

final class DragTouchClaimHandoffTests: XCTestCase {
    func testBeginLocalPreviewCreatesPendingClaimWithUniqueToken() {
        var handoff = makeHandoff()

        let firstToken = handoff.beginLocalPreview(at: timestamp(frame: 10, uptimeMs: 100))
        let secondToken = handoff.beginLocalPreview(at: timestamp(frame: 11, uptimeMs: 116))

        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertEqual(handoff.snapshot.token, secondToken)
        XCTAssertEqual(handoff.snapshot.state, .pending)
        XCTAssertEqual(handoff.snapshot.owner, .localPreview)
        XCTAssertTrue(handoff.snapshot.isPendingClaim)
    }

    func testClaimSuccessOnlyAppliesToCurrentToken() {
        var handoff = makeHandoff()
        let token = handoff.beginLocalPreview(at: timestamp(frame: 10, uptimeMs: 100))

        let success = handoff.reportClaimSucceeded(
            for: token,
            at: timestamp(frame: 11, uptimeMs: 116)
        )

        XCTAssertEqual(success, .applied)
        XCTAssertEqual(handoff.snapshot.state, .rootClaimed)
        XCTAssertTrue(handoff.snapshot.isRootClaimed)
        XCTAssertTrue(handoff.isCurrentOwner(.root))
        XCTAssertEqual(handoff.snapshot.claimLatencyMs, 16)
    }

    func testLateEventsFromPreviousTokenAreIgnoredAsStale() {
        var handoff = makeHandoff()
        let firstToken = handoff.beginLocalPreview(at: timestamp(frame: 10, uptimeMs: 100))
        let secondToken = handoff.beginLocalPreview(at: timestamp(frame: 11, uptimeMs: 116))

        let staleSuccess = handoff.reportClaimSucceeded(
            for: firstToken,
            at: timestamp(frame: 12, uptimeMs: 132)
        )
        let staleEnd = handoff.reportClaimEnded(for: firstToken)
        let staleCancel = handoff.reportClaimCancelled(
            for: firstToken,
            at: timestamp(frame: 12, uptimeMs: 132)
        )

        XCTAssertEqual(staleSuccess, .staleIgnored)
        XCTAssertEqual(staleEnd, .staleIgnored)
        XCTAssertEqual(staleCancel, .staleIgnored)
        XCTAssertEqual(handoff.snapshot.token, secondToken)
        XCTAssertEqual(handoff.snapshot.state, .pending)
        XCTAssertTrue(handoff.snapshot.isPendingClaim)
        XCTAssertEqual(handoff.snapshot.owner, .localPreview)
    }

    func testTimeoutBeyondBoundedWindowUsesTimeoutRestoreReason() {
        var handoff = makeHandoff()
        let token = handoff.beginLocalPreview(at: timestamp(frame: 10, uptimeMs: 100))

        let timeout = handoff.expirePendingClaimIfNeeded(
            at: timestamp(frame: 13, uptimeMs: 150)
        )
        let lateSuccess = handoff.reportClaimSucceeded(
            for: token,
            at: timestamp(frame: 13, uptimeMs: 150)
        )

        XCTAssertEqual(timeout, .applied)
        XCTAssertEqual(lateSuccess, .ignored)
        XCTAssertEqual(handoff.snapshot.state, .finished)
        XCTAssertEqual(handoff.snapshot.restoreReason, .timeout)
        XCTAssertFalse(handoff.snapshot.isRootClaimed)
        XCTAssertFalse(handoff.isCurrentOwner(.root))
    }

    func testPlaceholderAndRootOwnershipStayFalseBeforeClaimSuccess() {
        var handoff = makeHandoff()

        _ = handoff.beginLocalPreview(at: timestamp(frame: 10, uptimeMs: 100))

        XCTAssertFalse(handoff.snapshot.canShowPlaceholder)
        XCTAssertFalse(handoff.snapshot.isRootClaimed)
        XCTAssertFalse(handoff.isCurrentOwner(.root))
        XCTAssertTrue(handoff.isCurrentOwner(.localPreview))
    }

    private func makeHandoff() -> DragTouchClaimHandoff {
        DragTouchClaimHandoff(window: .boundedHandoff)
    }

    private func timestamp(frame: Int, uptimeMs: Int) -> DragTouchClaimTimestamp {
        DragTouchClaimTimestamp(frameIndex: frame, uptimeMs: uptimeMs)
    }
}
