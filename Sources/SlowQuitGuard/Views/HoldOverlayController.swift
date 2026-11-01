import AppKit
import Observation
import QuitGuardCore
import SwiftUI

@MainActor
final class HoldOverlayController {
    private var panel: PassivePanel?
    private var presentation: HoldPresentation?
    private var displayTask: Task<Void, Never>?
    private var generation = 0
    private let screenFrame: NSRect?
    private let screenForTarget: @MainActor (QuitTarget) -> NSRect?
    private var anchoredScreenFrame: NSRect?
    private var cachedIconTarget: ApplicationIdentity?
    private var cachedIcon: NSImage?
    private var iconTask: Task<Void, Never>?
    private let model = HoldOverlayModel()
    private(set) var hostingView: NSHostingView<HoldOverlayView>?

    init(screenFrame: NSRect? = nil,
         screenForTarget: @escaping @MainActor (QuitTarget) -> NSRect? = OverlayScreenResolver.visibleFrame) {
        self.screenFrame = screenFrame
        self.screenForTarget = screenForTarget
    }

    var isVisible: Bool { panel?.isVisible == true }
    var displayedFrame: NSRect? { panel?.frame }

    func warmUp() {
        if panel == nil { _ = makePanel() }
        hostingView?.layoutSubtreeIfNeeded()
    }

    func prepareTarget(_ target: QuitTarget?) {
        guard let target, target.identity != cachedIconTarget else { return }
        cachedIconTarget = target.identity
        cachedIcon = NSRunningApplication(processIdentifier: target.identity.processID)?.icon
        if cachedIcon == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.identity.bundleID) {
            cachedIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        if model.session?.target.identity == target.identity { model.targetIcon = cachedIcon }
    }

    func present(_ value: HoldPresentation?) {
        guard value != presentation else { return }
        // A target may close immediately after posting. Preserve its completed
        // frame instead of letting the following nil erase the confirmation.
        if value == nil, model.phase != .holding, isVisible, displayTask != nil { return }
        presentation = value
        generation += 1
        let token = generation
        displayTask?.cancel()
        switch value {
        case let .holding(session):
            prepare(session, phase: .holding)
            if isVisible { updatePanelGeometry(); return }
            showPanel()
        case let .completed(session):
            prepare(session, phase: .completed)
            showPanel()
            dismiss(after: .milliseconds(240), token: token)
        case let .failed(session, stoppedAt):
            prepare(session, phase: .failed)
            model.stoppedAt = stoppedAt
            showPanel()
            dismiss(after: .milliseconds(1000), token: token)
        case nil:
            hideNow()
        }
    }

    func dismissImmediately() {
        generation += 1
        displayTask?.cancel()
        hideNow()
    }

    private func prepare(_ session: HoldSession, phase: HoldOverlayPhase) {
        if model.session != session {
            anchoredScreenFrame = screenFrame ?? screenForTarget(session.target)
        }
        model.targetIcon = cachedIconTarget == session.target.identity ? cachedIcon : nil
        if cachedIconTarget != session.target.identity, phase == .holding {
            iconTask?.cancel()
            iconTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, self.model.session?.target.identity == session.target.identity else { return }
                self.prepareTarget(session.target)
            }
        }
        model.session = session
        model.phase = phase
        model.stoppedAt = nil
        model.animateExit = false
        model.visible = true
    }

    private func dismiss(after delay: Duration, token: Int) {
        displayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.model.animateExit = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self.model.visible = false
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, self.generation == token else { return }
            self.hideNow()
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        updatePanelGeometry()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in self?.updatePanelGeometry() }
    }

    private func updatePanelGeometry() {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        panel.setContentSize(NSSize(width: ceil(size.width), height: ceil(size.height)))
        if let frame = anchoredScreenFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2))
        }
    }

    private func hideNow() {
        model.animateExit = false
        model.visible = false
        panel?.orderOut(nil)
        model.session = nil
        presentation = nil
        displayTask = nil
        iconTask?.cancel()
        iconTask = nil
        anchoredScreenFrame = nil
    }

    private func makePanel() -> PassivePanel {
        let panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: HoldOverlayLayout.panelWidth,
            height: HoldOverlayLayout.minimumPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hosted = NSHostingView(rootView: HoldOverlayView(model: model))
        panel.contentView = hosted
        hostingView = hosted
        self.panel = panel
        return panel
    }
}

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum HoldOverlayPhase: Equatable {
    case holding, completed, failed
}

@MainActor
@Observable
final class HoldOverlayModel {
    var session: HoldSession?
    var phase: HoldOverlayPhase = .holding
    var stoppedAt: Double?
    var targetIcon: NSImage?
    var visible = false
    var animateExit = false
}
