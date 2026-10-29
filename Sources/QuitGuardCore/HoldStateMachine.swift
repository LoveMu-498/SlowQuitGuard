// SPDX-License-Identifier: GPL-2.0-or-later
// Swift reimplementation of SlowQuitApps (2026-10-30).
// Reference: https://github.com/dteoh/SlowQuitApps
// Upstream copyright (C) 2020 Douglas Teoh.
// Copyright (C) 2026 SlowQuitGuard contributors.
// See NOTICE and LICENSE for attribution and terms.

public struct ApplicationIdentity: Equatable, Sendable {
    public let processID: Int32
    public let bundleID: String
    public let launchTime: Double?

    public init(processID: Int32, bundleID: String, launchTime: Double? = nil) {
        self.processID = processID
        self.bundleID = bundleID
        self.launchTime = launchTime
    }
}

public struct QuitTarget: Equatable, Sendable {
    public let identity: ApplicationIdentity
    public let name: String

    public init(identity: ApplicationIdentity, name: String) {
        self.identity = identity
        self.name = name
    }
}

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
}

public struct KeyInput: Sendable {
    public enum Kind: Sendable { case down, up, modifiersChanged }
    public let kind: Kind
    public let keyCode: UInt16
    public let modifiers: KeyModifiers
    public let isRepeat: Bool

    public init(_ kind: Kind, keyCode: UInt16, modifiers: KeyModifiers, isRepeat: Bool = false) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

public struct HoldSession: Equatable, Sendable {
    public let target: QuitTarget
    public let keyCode: UInt16
    public let startedAt: Double
    public let duration: Double

    public init(target: QuitTarget, keyCode: UInt16, startedAt: Double, duration: Double) {
        self.target = target
        self.keyCode = keyCode
        self.startedAt = startedAt
        self.duration = duration
    }

    public func progress(at now: Double) -> Double {
        min(1, max(0, (now - startedAt) / duration))
    }

    public func remaining(at now: Double) -> Double {
        max(0, duration - max(0, now - startedAt))
    }
}

public struct HoldStateMachine: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case holding(HoldSession)
        case waitingForRelease(UInt16)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var appSwitcherActive = false
    private var releaseObserved = false

    public init() {}

    public var hold: HoldSession? {
        if case let .holding(session) = phase { return session }
        return nil
    }

    /// Returns true only for a Q event whose delivery this machine owns.
    @discardableResult
    public mutating func handle(
        _ input: KeyInput,
        now: Double,
        target: QuitTarget?,
        qKeyCodes: Set<UInt16>,
        enabled: Bool,
        duration: Double
    ) -> Bool {
        if input.kind == .modifiersChanged && !input.modifiers.contains(.command) {
            appSwitcherActive = false
        }
        if input.kind == .down && input.keyCode == 48 && input.modifiers.contains(.command) {
            appSwitcherActive = true
            cancel()
        }

        // A fresh press needs a matching key-up or an observed physical release.
        // Some input tools emit repeated down events without the repeat flag.
        if case let .waitingForRelease(key) = phase,
           input.keyCode == key, input.kind == .down, releaseObserved {
            phase = .idle
            releaseObserved = false
        }

        if let session = hold,
           !enabled || target?.identity != session.target.identity {
            cancel()
        }

        switch phase {
        case .idle:
            guard enabled, !appSwitcherActive,
                  input.kind == .down, input.modifiers == [.command],
                  qKeyCodes.contains(input.keyCode), let target else { return false }
            guard !input.isRepeat else {
                phase = .waitingForRelease(input.keyCode)
                return true
            }
            phase = .holding(HoldSession(
                target: target, keyCode: input.keyCode,
                startedAt: now, duration: min(3, max(0.5, duration))
            ))
            return true

        case let .holding(session):
            if input.keyCode == session.keyCode && input.kind == .up {
                phase = .idle
                releaseObserved = false
                return true
            }
            if input.modifiers != [.command] ||
                (input.kind == .down && input.keyCode != session.keyCode) {
                cancel()
            }
            return input.keyCode == session.keyCode && input.kind != .modifiersChanged

        case let .waitingForRelease(key):
            guard input.keyCode == key, input.kind != .modifiersChanged else { return false }
            if input.kind == .up { phase = .idle; releaseObserved = false }
            return true
        }
    }

    public mutating func cancel() {
        if case let .holding(session) = phase {
            phase = .waitingForRelease(session.keyCode)
            releaseObserved = false
        }
    }

    public mutating func connectionInterrupted() {
        cancel()
        releaseObserved = false
        appSwitcherActive = false
    }

    public var ownedKey: UInt16? {
        switch phase {
        case .idle: nil
        case let .holding(session): session.keyCode
        case let .waitingForRelease(key): key
        }
    }

    public mutating func observePhysicalRelease(of key: UInt16) {
        guard ownedKey == key else { return }
        cancel()
        releaseObserved = true
    }

    /// A deadline approves at most one request; it never depends on key repeat.
    public mutating func approveIfDue(
        now: Double, target: QuitTarget?, shortcutStillHeld: Bool, enabled: Bool
    ) -> HoldSession? {
        guard let session = hold else { return nil }
        guard enabled, shortcutStillHeld,
              target?.identity == session.target.identity else {
            cancel()
            return nil
        }
        guard now - session.startedAt >= session.duration else { return nil }
        phase = .waitingForRelease(session.keyCode)
        releaseObserved = false
        return session
    }
}
