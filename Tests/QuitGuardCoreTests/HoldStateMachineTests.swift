import Testing
@testable import QuitGuardCore

private let q: UInt16 = 12
private let app = QuitTarget(identity: .init(processID: 101, bundleID: "test.editor", launchTime: 1), name: "Editor")
private let otherApp = QuitTarget(identity: .init(processID: 102, bundleID: "test.browser", launchTime: 2), name: "Browser")

private func send(
    _ machine: inout HoldStateMachine, _ kind: KeyInput.Kind = .down,
    key: UInt16 = q, modifiers: KeyModifiers = [.command],
    time: Double = 10, target: QuitTarget? = app,
    enabled: Bool = true, repeating: Bool = false, qCodes: Set<UInt16> = [q]
) -> Bool {
    machine.handle(.init(kind, keyCode: key, modifiers: modifiers, isRepeat: repeating),
                   now: time, target: target, qKeyCodes: qCodes, enabled: enabled, duration: 1)
}

@Test func shortPressIsSuppressedAndCancelled() {
    var machine = HoldStateMachine()
    #expect(send(&machine))
    #expect(send(&machine, .up, time: 10.2))
    #expect(machine.phase == .idle)
    #expect(machine.approveIfDue(now: 12, target: app, shortcutStillHeld: false, enabled: true) == nil)
}

@Test func deadlineWorksWithoutAnyRepeatEvents() {
    var machine = HoldStateMachine()
    #expect(send(&machine))
    #expect(machine.approveIfDue(now: 10.9, target: app, shortcutStillHeld: true, enabled: true) == nil)
    let approval = machine.approveIfDue(now: 11, target: app, shortcutStillHeld: true, enabled: true)
    #expect(approval?.target == app)
    #expect(approval?.startedAt == 10)
}

@Test func oneHoldCannotApproveTwiceOrRestartFromRepeats() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(machine.approveIfDue(now: 11, target: app, shortcutStillHeld: true, enabled: true) != nil)
    #expect(send(&machine, time: 11.1, repeating: true))
    #expect(machine.approveIfDue(now: 12.5, target: app, shortcutStillHeld: true, enabled: true) == nil)
    #expect(send(&machine, .up, time: 13))
    #expect(send(&machine, time: 14))
    #expect(machine.approveIfDue(now: 15, target: app, shortcutStillHeld: true, enabled: true) != nil)
}

@Test func repeatDoesNotResetStartTime() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    for time in [10.4, 10.7, 10.9] { #expect(send(&machine, time: time, repeating: true)) }
    #expect(machine.hold?.startedAt == 10)
    #expect(machine.approveIfDue(now: 11, target: app, shortcutStillHeld: true, enabled: true) != nil)
}

@Test func repeatedDownWithoutRepeatFlagDoesNotRestartTheHold() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    let initialSession = machine.hold
    for time in [10.1, 10.3, 10.6, 10.8] {
        #expect(send(&machine, time: time))
        #expect(machine.hold == initialSession)
    }
    #expect(machine.approveIfDue(now: 11, target: app, shortcutStillHeld: true, enabled: true) != nil)
}

@Test func unmarkedDownAfterCompletionCannotStartAnotherHold() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(machine.approveIfDue(now: 11, target: app, shortcutStillHeld: true, enabled: true) != nil)
    #expect(send(&machine, time: 11.1))
    #expect(machine.hold == nil)
    #expect(machine.approveIfDue(now: 12.5, target: app, shortcutStillHeld: true, enabled: true) == nil)
}

@Test func commandReleasedBeforeQDrainsTheOwnedQEvents() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(!send(&machine, .modifiersChanged, key: 55, modifiers: [], time: 10.1))
    #expect(machine.hold == nil)
    #expect(send(&machine, modifiers: [], time: 10.2, repeating: true))
    #expect(send(&machine, .up, modifiers: [], time: 10.3))
    #expect(machine.phase == .idle)
}

@Test(arguments: [KeyModifiers.control, .option, .shift, .function])
func otherCommandCombinationsPassThrough(extra: KeyModifiers) {
    var machine = HoldStateMachine()
    #expect(!send(&machine, modifiers: [.command, extra]))
    #expect(machine.phase == .idle)
}

@Test func addingAModifierCancelsAnExistingHold() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(!send(&machine, .modifiersChanged, key: 59, modifiers: [.command, .control], time: 10.3))
    #expect(machine.hold == nil)
    #expect(machine.approveIfDue(now: 11.5, target: app, shortcutStillHeld: true, enabled: true) == nil)
}

@Test func ordinaryQAndUnprotectedTargetsAreUntouched() {
    var machine = HoldStateMachine()
    #expect(!send(&machine, modifiers: []))
    #expect(!send(&machine, target: nil))
    #expect(!send(&machine, enabled: false))
    #expect(!send(&machine, key: 13))
}

@Test func targetSwitchCancelsWithoutQuittingEitherApplication() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(machine.approveIfDue(now: 11, target: otherApp, shortcutStillHeld: true, enabled: true) == nil)
    #expect(machine.hold == nil)
    #expect(send(&machine, .up, target: otherApp))
}

@Test func aReusedPIDIsNotTheSameTarget() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    let replacement = QuitTarget(identity: .init(processID: 101, bundleID: "test.editor", launchTime: 99), name: "Editor")
    #expect(machine.approveIfDue(now: 11, target: replacement, shortcutStillHeld: true, enabled: true) == nil)
}

@Test func missedKeyUpCannotCauseAQuitAtTheDeadline() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(machine.approveIfDue(now: 11.2, target: app, shortcutStillHeld: false, enabled: true) == nil)
    #expect(machine.hold == nil)
}

@Test func interruptionCancelsAndRequiresANewPress() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    machine.connectionInterrupted()
    #expect(machine.hold == nil)
    #expect(send(&machine, time: 20, repeating: true))
    #expect(machine.approveIfDue(now: 22, target: app, shortcutStillHeld: true, enabled: true) == nil)
    // The release may have happened while no tap existed.
    machine.observePhysicalRelease(of: q)
    #expect(send(&machine, time: 23))
    #expect(machine.approveIfDue(now: 24, target: app, shortcutStillHeld: true, enabled: true) != nil)
}

@Test func physicalReleaseAfterAMissedKeyUpAllowsANewHold() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    machine.observePhysicalRelease(of: q)
    #expect(machine.hold == nil)
    #expect(send(&machine, time: 10.8))
    #expect(machine.hold?.startedAt == 10.8)
    #expect(machine.approveIfDue(now: 11, target: app, shortcutStillHeld: true, enabled: true) == nil)
}

@Test func sessionProgressAndDeadlineUseTheSameClock() {
    let session = HoldSession(target: app, keyCode: q, startedAt: 10, duration: 1)
    #expect(session.progress(at: 9) == 0)
    #expect(session.progress(at: 10.5) == 0.5)
    #expect(session.remaining(at: 10.5) == 0.5)
    #expect(session.progress(at: 11) == 1)
    #expect(session.remaining(at: 11.1) == 0)
}

@Test func resumingMidRepeatCannotQuitImmediately() {
    var machine = HoldStateMachine()
    #expect(send(&machine, repeating: true))
    #expect(machine.hold == nil)
    #expect(send(&machine, .up))
    #expect(send(&machine, time: 30))
    #expect(machine.hold?.startedAt == 30)
}

@Test func appSwitcherQIsLeftToTheSystem() {
    var machine = HoldStateMachine()
    #expect(!send(&machine, key: 48))
    #expect(!send(&machine))
    #expect(!send(&machine, .up))
    #expect(!send(&machine, .modifiersChanged, key: 55, modifiers: []))
    #expect(send(&machine, time: 20))
}

@Test func escapeCancelsButIsNotConsumed() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(!send(&machine, key: 53))
    #expect(machine.hold == nil)
    #expect(send(&machine, .up))
}

@Test func resolvedLayoutKeyIsUsedInsteadOfHardcodedPhysicalQ() {
    var machine = HoldStateMachine()
    #expect(!send(&machine, key: q, qCodes: [0]))
    #expect(send(&machine, key: 0, qCodes: [0]))
    #expect(machine.hold?.keyCode == 0)
}

@Test func pausingWhileHoldingCannotApproveAQuit() {
    var machine = HoldStateMachine()
    _ = send(&machine)
    #expect(machine.approveIfDue(now: 11, target: app, shortcutStillHeld: true, enabled: false) == nil)
    #expect(send(&machine, .up, enabled: false))
    #expect(!send(&machine, time: 12, enabled: false))
}
