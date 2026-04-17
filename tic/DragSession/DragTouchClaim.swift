import Foundation

struct DragTouchClaimToken: Equatable, Hashable, Codable {
    let rawValue: UInt64
}

struct DragTouchClaimTimestamp: Equatable, Codable {
    var frameIndex: Int
    var uptimeMs: Int
}

struct DragTouchClaimWindow: Equatable, Codable {
    var maxPendingFrames: Int
    var maxPendingUptimeMs: Int?

    static let boundedHandoff = Self(
        maxPendingFrames: 2,
        maxPendingUptimeMs: nil
    )

    func status(
        since start: DragTouchClaimTimestamp,
        at now: DragTouchClaimTimestamp
    ) -> DragTouchClaimWindowStatus {
        let elapsedFrames = max(0, now.frameIndex - start.frameIndex)
        let elapsedUptimeMs = max(0, now.uptimeMs - start.uptimeMs)
        let expiredByFrameBudget = elapsedFrames > maxPendingFrames
        let expiredByTimeBudget = maxPendingUptimeMs.map { elapsedUptimeMs > $0 } ?? false

        return DragTouchClaimWindowStatus(
            elapsedFrames: elapsedFrames,
            elapsedUptimeMs: elapsedUptimeMs,
            remainingFrameBudget: max(0, maxPendingFrames - elapsedFrames),
            isExpired: expiredByFrameBudget || expiredByTimeBudget
        )
    }
}

struct DragTouchClaimWindowStatus: Equatable, Codable {
    var elapsedFrames: Int
    var elapsedUptimeMs: Int
    var remainingFrameBudget: Int
    var isExpired: Bool
}

enum DragTouchClaimState: String, Equatable, Codable {
    case idle
    case pending
    case rootClaimed
    case finished
}

enum DragTouchClaimOwner: String, Equatable, Codable {
    case none
    case localPreview
    case root
}

enum DragTouchClaimRestoreReason: String, Equatable, Codable {
    case timeout
    case cancelled
}

enum DragTouchClaimEventResult: Equatable {
    case applied
    case staleIgnored
    case ignored
}

struct DragTouchClaimSnapshot: Equatable, Codable {
    var token: DragTouchClaimToken? = nil
    var state: DragTouchClaimState = .idle
    var owner: DragTouchClaimOwner = .none
    var localPreviewStartedAt: DragTouchClaimTimestamp? = nil
    var rootClaimedAt: DragTouchClaimTimestamp? = nil
    var restoreReason: DragTouchClaimRestoreReason? = nil
    var window: DragTouchClaimWindow = .boundedHandoff

    var isPendingClaim: Bool {
        token != nil && state == .pending && owner == .localPreview
    }

    var isRootClaimed: Bool {
        token != nil && state == .rootClaimed && owner == .root
    }

    var canShowPlaceholder: Bool {
        isRootClaimed
    }

    var claimLatencyMs: Int? {
        guard let startedAt = localPreviewStartedAt,
              let claimedAt = rootClaimedAt else {
            return nil
        }
        return max(0, claimedAt.uptimeMs - startedAt.uptimeMs)
    }

    func windowStatus(at timestamp: DragTouchClaimTimestamp) -> DragTouchClaimWindowStatus? {
        guard let localPreviewStartedAt else { return nil }
        return window.status(since: localPreviewStartedAt, at: timestamp)
    }

    func isOwner(_ candidate: DragTouchClaimOwner) -> Bool {
        owner == candidate
    }
}

protocol DragTouchClaimManaging {
    var snapshot: DragTouchClaimSnapshot { get }

    @discardableResult
    mutating func beginLocalPreview(at timestamp: DragTouchClaimTimestamp) -> DragTouchClaimToken

    @discardableResult
    mutating func reportClaimSucceeded(
        for token: DragTouchClaimToken,
        at timestamp: DragTouchClaimTimestamp
    ) -> DragTouchClaimEventResult

    @discardableResult
    mutating func reportClaimEnded(
        for token: DragTouchClaimToken
    ) -> DragTouchClaimEventResult

    @discardableResult
    mutating func reportClaimCancelled(
        for token: DragTouchClaimToken,
        at timestamp: DragTouchClaimTimestamp
    ) -> DragTouchClaimEventResult

    @discardableResult
    mutating func expirePendingClaimIfNeeded(
        at timestamp: DragTouchClaimTimestamp
    ) -> DragTouchClaimEventResult

    func isCurrentOwner(_ owner: DragTouchClaimOwner) -> Bool
}

struct DragTouchClaimHandoff: DragTouchClaimManaging {
    private(set) var snapshot: DragTouchClaimSnapshot
    private var nextTokenRawValue: UInt64

    init(
        window: DragTouchClaimWindow = .boundedHandoff,
        startingTokenRawValue: UInt64 = 1
    ) {
        self.snapshot = DragTouchClaimSnapshot(window: window)
        self.nextTokenRawValue = startingTokenRawValue
    }

    @discardableResult
    mutating func beginLocalPreview(at timestamp: DragTouchClaimTimestamp) -> DragTouchClaimToken {
        let token = DragTouchClaimToken(rawValue: nextTokenRawValue)
        nextTokenRawValue += 1

        snapshot = DragTouchClaimSnapshot(
            token: token,
            state: .pending,
            owner: .localPreview,
            localPreviewStartedAt: timestamp,
            rootClaimedAt: nil,
            restoreReason: nil,
            window: snapshot.window
        )
        return token
    }

    @discardableResult
    mutating func reportClaimSucceeded(
        for token: DragTouchClaimToken,
        at timestamp: DragTouchClaimTimestamp
    ) -> DragTouchClaimEventResult {
        guard matchesCurrentToken(token) else { return staleResult(for: token) }
        if expirePendingClaimIfNeeded(at: timestamp) == .applied {
            return .ignored
        }
        guard snapshot.state == .pending else { return .ignored }

        snapshot.state = .rootClaimed
        snapshot.owner = .root
        snapshot.rootClaimedAt = timestamp
        snapshot.restoreReason = nil
        return .applied
    }

    @discardableResult
    mutating func reportClaimEnded(
        for token: DragTouchClaimToken
    ) -> DragTouchClaimEventResult {
        guard matchesCurrentToken(token) else { return staleResult(for: token) }
        guard snapshot.state != .idle else { return .ignored }

        snapshot = DragTouchClaimSnapshot(window: snapshot.window)
        return .applied
    }

    @discardableResult
    mutating func reportClaimCancelled(
        for token: DragTouchClaimToken,
        at timestamp: DragTouchClaimTimestamp
    ) -> DragTouchClaimEventResult {
        guard matchesCurrentToken(token) else { return staleResult(for: token) }
        if expirePendingClaimIfNeeded(at: timestamp) == .applied {
            return .ignored
        }
        guard snapshot.state == .pending || snapshot.state == .rootClaimed else {
            return .ignored
        }

        snapshot.state = .finished
        snapshot.owner = .none
        snapshot.restoreReason = .cancelled
        return .applied
    }

    @discardableResult
    mutating func expirePendingClaimIfNeeded(
        at timestamp: DragTouchClaimTimestamp
    ) -> DragTouchClaimEventResult {
        guard snapshot.state == .pending else { return .ignored }
        guard let status = snapshot.windowStatus(at: timestamp),
              status.isExpired else {
            return .ignored
        }

        snapshot.state = .finished
        snapshot.owner = .none
        snapshot.restoreReason = .timeout
        return .applied
    }

    func isCurrentOwner(_ owner: DragTouchClaimOwner) -> Bool {
        snapshot.isOwner(owner)
    }

    private func matchesCurrentToken(_ token: DragTouchClaimToken) -> Bool {
        snapshot.token == token
    }

    private func staleResult(for token: DragTouchClaimToken) -> DragTouchClaimEventResult {
        guard let currentToken = snapshot.token else { return .ignored }
        return currentToken == token ? .ignored : .staleIgnored
    }
}
