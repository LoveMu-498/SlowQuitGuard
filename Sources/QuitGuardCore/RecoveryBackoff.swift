public struct RecoveryBackoff: Sendable {
    public private(set) var failureCount = 0
    public private(set) var nextAttemptAt: Double = 0

    public init() {}

    public func canAttempt(at now: Double) -> Bool { now >= nextAttemptAt }

    public mutating func failed(at now: Double) {
        failureCount = min(failureCount + 1, 7)
        let delays: [Double] = [0.5, 1, 2, 4, 8, 15, 30]
        nextAttemptAt = now + delays[failureCount - 1]
    }

    public mutating func reset() {
        failureCount = 0
        nextAttemptAt = 0
    }
}
