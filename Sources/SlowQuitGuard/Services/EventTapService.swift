// SPDX-License-Identifier: GPL-2.0-or-later
// Swift reimplementation of SlowQuitApps (2026-10-30).
// Reference: https://github.com/dteoh/SlowQuitApps
// Upstream copyright (C) 2020 Douglas Teoh.
// Copyright (C) 2026 SlowQuitGuard contributors.
// See NOTICE and LICENSE for attribution and terms.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import OSLog
import QuitGuardCore

// Control data is lock-protected. All tap, timer and state-machine access is
// confined to the named worker thread, including its C callback.
final class EventTapService: @unchecked Sendable {
    private let lock = NSLock()
    private var policy: RuntimePolicy
    private var workerLoop: CFRunLoop?
    private var stopping = false
    private let onChange: @Sendable (ServiceSnapshot) -> Void
    private let logger = Logger(subsystem: "org.slowquitguard.SlowQuitGuard", category: "Protection")

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var healthTimer: CFRunLoopTimer?
    private var holdTimer: CFRunLoopTimer?
    private var machine = HoldStateMachine()
    private var originalQuitEvent: CGEvent?
    private var recovery = RecoveryBackoff()
    private var snapshot = ServiceSnapshot()
    private var lastPublished: ServiceSnapshot?
    private var stableSince: Double?
    private var pendingRecoveryReason: String?

    private static let eventTag: Int64 = 0x5351_4755_4152_4401
    private static var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

    init(policy: RuntimePolicy, onChange: @escaping @Sendable (ServiceSnapshot) -> Void) {
        self.policy = policy
        self.onChange = onChange
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "SlowQuitGuard.Keyboard"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func updatePolicy(_ value: RuntimePolicy) {
        let changed = lock.withLock {
            guard policy != value else { return false }
            policy = value
            return true
        }
        guard changed else { return }
        perform { [self] in
            cancelHold()
            refresh()
        }
    }

    func reconnect() {
        perform { [self] in
            cancelHold()
            removeTap()
            recovery.reset()
            pendingRecoveryReason = "手动修复保护"
            snapshot.state = .starting
            publish()
            refresh()
        }
    }

    func stop() {
        lock.withLock { stopping = true }
        perform { CFRunLoopStop(CFRunLoopGetCurrent()) }
    }

    private func perform(_ action: @escaping @Sendable () -> Void) {
        guard let loop = lock.withLock({ workerLoop }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, action)
        CFRunLoopWakeUp(loop)
    }

    private func run() {
        autoreleasepool {
            let loop = CFRunLoopGetCurrent()
            lock.withLock { workerLoop = loop }
            guard !lock.withLock({ stopping }) else { return }
            healthTimer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0) { [self] _ in
                autoreleasepool { refresh() }
            }
            CFRunLoopAddTimer(loop, healthTimer, .commonModes)
            refresh()
            CFRunLoopRun()
            cancelHold()
            removeTap()
            if let healthTimer { CFRunLoopTimerInvalidate(healthTimer) }
            healthTimer = nil
            lock.withLock { workerLoop = nil }
        }
    }

    private var currentPolicy: RuntimePolicy { lock.withLock { policy } }

    private func refresh() {
        guard !lock.withLock({ stopping }) else {
            CFRunLoopStop(CFRunLoopGetCurrent())
            return
        }
        let policy = currentPolicy
        let oldPermissions = [snapshot.accessibilityGranted, snapshot.postingGranted, snapshot.listeningGranted]
        snapshot.accessibilityGranted = AXIsProcessTrusted()
        snapshot.postingGranted = CGPreflightPostEventAccess()
        snapshot.listeningGranted = CGPreflightListenEventAccess()
        snapshot.secureInput = IsSecureEventInputEnabled()
        if oldPermissions != [snapshot.accessibilityGranted, snapshot.postingGranted, snapshot.listeningGranted] {
            recovery.reset()
        }

        let blocked: ProtectionState?
        if !policy.enabled { blocked = .paused }
        else if !policy.sessionActive { blocked = .sessionInactive }
        else if !snapshot.accessibilityGranted { blocked = .accessibilityRequired }
        else if snapshot.secureInput { blocked = .secureInput }
        else if !snapshot.postingGranted { blocked = .postingPermissionRequired }
        else { blocked = nil }

        if let blocked {
            cancelHold()
            removeTap()
            recovery.reset()
            snapshot.state = blocked
            publish()
            return
        }

        let now = Self.now
        guard recovery.canAttempt(at: now) else {
            publish()
            return
        }

        if let tap, CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) {
            reconcilePhysicalRelease()
            if let stableSince, now - stableSince >= 10 { recovery.reset() }
            snapshot.state = .ready
            snapshot.tapEnabled = true
            publish()
            return
        }

        cancelHold()
        let wasExistingTap = tap != nil
        if let tap, CFMachPortIsValid(tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                connected(reason: pendingRecoveryReason ?? "监听自动恢复")
                return
            }
        }
        removeTap()
        if createTap() {
            connected(reason: pendingRecoveryReason ?? (wasExistingTap ? "监听已重建" : nil))
        } else {
            recovery.failed(at: now)
            snapshot.state = .connectionFailed(checkInputMonitoring: !snapshot.listeningGranted)
            pendingRecoveryReason = "键盘保护连接失败后重新连接"
            publish()
        }
    }

    private func createTap() -> Bool {
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: quitGuardCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let runSource = CFMachPortCreateRunLoopSource(nil, port, 0) else { return false }
        tap = port
        source = runSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    private func removeTap() {
        machine.connectionInterrupted()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        stableSince = nil
        snapshot.tapEnabled = false
    }

    private func connected(reason: String?) {
        reconcilePhysicalRelease()
        stableSince = Self.now
        snapshot.state = .ready
        snapshot.tapEnabled = true
        if let reason {
            snapshot.recoveryCount += 1
            snapshot.lastRecoveryReason = reason
            snapshot.lastRecoveryDate = Date()
        }
        pendingRecoveryReason = nil
        publish()
    }

    fileprivate func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelHold()
            machine.connectionInterrupted()
            stableSince = nil
            pendingRecoveryReason = type == .tapDisabledByTimeout ? "监听超时后恢复" : "系统停用监听后恢复"
            recovery.failed(at: Self.now)
            snapshot.state = .recovering
            snapshot.tapEnabled = false
            publish()
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.eventTag else {
            return Unmanaged.passUnretained(event)
        }
        let kind: KeyInput.Kind
        switch type {
        case .keyDown: kind = .down
        case .keyUp: kind = .up
        case .flagsChanged: kind = .modifiersChanged
        default: return Unmanaged.passUnretained(event)
        }
        guard let keyCode = UInt16(exactly: event.getIntegerValueField(.keyboardEventKeycode)) else {
            return Unmanaged.passUnretained(event)
        }
        let policy = currentPolicy
        let before = machine.hold
        let input = KeyInput(kind,
            keyCode: keyCode,
            modifiers: KeyModifiers(event.flags),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        let suppress = machine.handle(input, now: Self.now, target: policy.target,
            qKeyCodes: policy.qKeyCodes,
            enabled: policy.enabled && policy.sessionActive && snapshot.state == .ready,
            duration: policy.duration)
        if before != machine.hold {
            originalQuitEvent = machine.hold == nil ? nil : event.copy()
            updateHoldPresentation()
        }
        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func updateHoldPresentation(completed: HoldSession? = nil) {
        if let holdTimer { CFRunLoopTimerInvalidate(holdTimer) }
        holdTimer = nil
        if let hold = machine.hold { snapshot.holdPresentation = .holding(hold) }
        else { snapshot.holdPresentation = completed.map(HoldPresentation.completed) }
        if machine.hold != nil {
            holdTimer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + 1.0 / 60, 1.0 / 60, 0, 0) { [self] _ in
                autoreleasepool { checkHold() }
            }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), holdTimer, .commonModes)
        }
        publish()
    }

    private func cancelHold() {
        machine.cancel()
        originalQuitEvent = nil
        if let holdTimer { CFRunLoopTimerInvalidate(holdTimer) }
        holdTimer = nil
        snapshot.holdPresentation = nil
    }

    private func reconcilePhysicalRelease() {
        if case let .waitingForRelease(key) = machine.phase,
           !CGEventSource.keyState(.hidSystemState, key: key) {
            machine.observePhysicalRelease(of: key)
        }
    }

    private func shortcutIsHeld(_ key: UInt16) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: key) &&
            KeyModifiers(CGEventSource.flagsState(.hidSystemState)) == [.command]
    }

    private func checkHold() {
        guard let hold = machine.hold else { return }
        let policy = currentPolicy
        let now = Self.now
        let physicallyHeld = shortcutIsHeld(hold.keyCode)
        let operational = policy.enabled && policy.sessionActive && snapshot.state == .ready &&
            policy.target?.identity == hold.target.identity
        guard operational, physicallyHeld else {
            cancelHold()
            if !CGEventSource.keyState(.hidSystemState, key: hold.keyCode) {
                machine.observePhysicalRelease(of: hold.keyCode)
            }
            publish()
            return
        }
        guard now - hold.startedAt >= hold.duration else { return }

        let actualTarget = CurrentApplication.target()
        let healthy = AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled() &&
            tap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } == true
        let approval = machine.approveIfDue(now: now, target: actualTarget,
            shortcutStillHeld: shortcutIsHeld(hold.keyCode), enabled: operational && healthy)
        let original = originalQuitEvent
        var sentSession: HoldSession?
        if let approval, let original,
           let down = original.copy(), let up = original.copy(),
           let replaySource = CGEventSource(stateID: .privateState),
           currentPolicy == policy, shortcutIsHeld(approval.keyCode),
           CurrentApplication.target()?.identity == approval.target.identity {
            down.type = .keyDown
            up.type = .keyUp
            for event in [down, up] {
                event.setSource(replaySource)
                event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
                event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                event.timestamp = DispatchTime.now().uptimeNanoseconds
            }
            down.postToPid(approval.target.identity.processID)
            up.postToPid(approval.target.identity.processID)
            sentSession = approval
            logger.info("A normal quit shortcut was sent to the captured application.")
        }
        originalQuitEvent = nil
        updateHoldPresentation(completed: sentSession)
        if !healthy { refresh() }
    }

    private func publish() {
        guard snapshot != lastPublished else { return }
        snapshot.revision += 1
        if snapshot.state != lastPublished?.state {
            logger.info("Protection state: \(self.snapshot.state.title, privacy: .public)")
        }
        lastPublished = snapshot
        onChange(snapshot)
    }
}

private func quitGuardCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
        .receive(type: type, event: event)
}
