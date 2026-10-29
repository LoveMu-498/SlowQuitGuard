import Testing
@testable import QuitGuardCore

@Test func initialConnectionIsImmediate() {
    #expect(RecoveryBackoff().canAttempt(at: 0))
}

@Test func repeatedFailuresWaitAndCannotCreateABusyRetryLoop() {
    var recovery = RecoveryBackoff()
    recovery.failed(at: 10)
    #expect(!recovery.canAttempt(at: 10.4))
    #expect(recovery.canAttempt(at: 10.5))
    recovery.failed(at: 10.5)
    #expect(!recovery.canAttempt(at: 11.4))
    #expect(recovery.canAttempt(at: 11.5))
    for _ in 0..<20 { recovery.failed(at: 100) }
    #expect(!recovery.canAttempt(at: 129))
    #expect(recovery.canAttempt(at: 130))
}

@Test func manualRetryOrAStableConnectionClearsTheWait() {
    var recovery = RecoveryBackoff()
    for _ in 0..<7 { recovery.failed(at: 10) }
    recovery.reset()
    #expect(recovery.canAttempt(at: 10))
    recovery.failed(at: 10)
    #expect(recovery.canAttempt(at: 10.5))
}
