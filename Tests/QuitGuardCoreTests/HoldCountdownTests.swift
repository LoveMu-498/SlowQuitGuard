import Testing
@testable import QuitGuardCore

@Test func countdownDoesNotDisplayZeroBeforeTheDeadline() {
    let hold = HoldSession(target: .init(identity: .init(processID: 123, bundleID: "test.editor"), name: "编辑器"),
                           keyCode: 12, startedAt: 100, duration: 1)
    #expect(hold.remainingTenths(at: 100) == 10)
    #expect(hold.remainingTenths(at: 100.2) == 8)
    #expect(hold.remainingTenths(at: 100.951) == 1)
    #expect(hold.remainingTenths(at: 100.99999) == 1)
    #expect(hold.remainingTenths(at: 101) == 0)
    #expect(hold.remainingTenths(at: 102) == 0)
    #expect(hold.remainingTenths(at: 99) == 10)
    #expect(hold.startedAt + hold.duration == 101)
}
