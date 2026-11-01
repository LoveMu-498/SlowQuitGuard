import AppKit
@preconcurrency import ApplicationServices
import Observation
import QuitGuardCore

@MainActor
@Observable
final class PermissionCoordinator {
    private(set) var stage: PermissionStage = .checking
    private(set) var access = PermissionAccess(accessibility: false, eventPosting: false, inputMonitoring: false)
    private(set) var guideVisible = false
    private(set) var lastCheckStillMissing = false

    @ObservationIgnored var onPresentGuide: (() -> Void)?
    @ObservationIgnored var onRefreshProtection: (() -> Void)?
    @ObservationIgnored private let readAccess: () -> PermissionAccess
    @ObservationIgnored private let requestAccess: (PermissionRequirement) -> Void
    @ObservationIgnored private let openDestination: (PermissionRequirement) -> Void
    @ObservationIgnored private var progression = PermissionProgression()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var needsInputMonitoring = false

    init(readAccess: @escaping () -> PermissionAccess,
         requestAccess: @escaping (PermissionRequirement) -> Void,
         openSettings: @escaping (PermissionRequirement) -> Void) {
        self.readAccess = readAccess
        self.requestAccess = requestAccess
        self.openDestination = openSettings
    }

    static func live() -> PermissionCoordinator {
        PermissionCoordinator(readAccess: {
            PermissionAccess(accessibility: AXIsProcessTrusted(), eventPosting: CGPreflightPostEventAccess(),
                             inputMonitoring: CGPreflightListenEventAccess())
        }, requestAccess: { kind in
            switch kind {
            case .accessibility:
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            case .eventPosting: _ = CGRequestPostEventAccess()
            case .inputMonitoring: _ = CGRequestListenEventAccess()
            }
        }, openSettings: { kind in
            NSWorkspace.shared.open(kind.settingsDestination.url)
        })
    }

    func showIfNeeded() {
        refresh(advance: false)
        guard stage != .ready else { return }
        guideVisible = true
        onPresentGuide?()
        beginPolling()
        refresh(advance: true)
    }

    func refresh(advance: Bool = true) {
        var fresh = readAccess()
        fresh.inputMonitoringRequired = needsInputMonitoring
        apply(fresh, advance: advance, reconnect: true)
    }

    func acceptRuntimeAccess(_ fresh: PermissionAccess, inputMonitoringRequired: Bool? = nil) {
        if let inputMonitoringRequired { needsInputMonitoring = inputMonitoringRequired }
        var fresh = fresh
        fresh.inputMonitoringRequired = needsInputMonitoring
        apply(fresh, advance: true, reconnect: false)
    }

    private func apply(_ fresh: PermissionAccess, advance: Bool, reconnect: Bool) {
        let previous = access.nextRequirement
        access = fresh
        switch fresh.nextRequirement {
        case .accessibility: stage = .accessibility
        case .eventPosting: stage = .posting
        case .inputMonitoring: stage = .inputMonitoring
        case nil: stage = .ready
        }
        if previous != fresh.nextRequirement {
            lastCheckStillMissing = false
            if guideVisible { onPresentGuide?() }
            if reconnect, fresh.nextRequirement == nil { onRefreshProtection?() }
        }
        if advance && guideVisible, let next = progression.automaticRequest(for: fresh) {
            requestAccess(next)
        }
    }

    func checkAndContinue() {
        let previous = access.nextRequirement
        refresh(advance: true)
        lastCheckStillMissing = access.nextRequirement != nil && access.nextRequirement == previous
        onRefreshProtection?()
        onPresentGuide?()
    }

    func openSettings(for kind: PermissionRequirement) {
        refresh(advance: false)
        if !access.isGranted(kind) {
            progression.recordRequest(kind)
            requestAccess(kind)
        }
        openDestination(kind)
    }

    func request(_ kind: PermissionRequirement) {
        guideVisible = true
        refresh(advance: false)
        onPresentGuide?()
        beginPolling()
        openSettings(for: kind)
    }

    func setInputMonitoringRequired(_ required: Bool) {
        needsInputMonitoring = required
        refresh(advance: true)
    }

    func guideDidClose() {
        guideVisible = false
        pollTask?.cancel()
        pollTask = nil
    }

    private func beginPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, self.guideVisible else { return }
                self.refresh()
            }
        }
    }
}
