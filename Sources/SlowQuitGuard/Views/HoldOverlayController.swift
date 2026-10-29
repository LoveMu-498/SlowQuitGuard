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
    private let model = HoldOverlayModel()
    private(set) var hostingView: NSHostingView<HoldOverlayView>?

    init(screenFrame: NSRect? = nil) { self.screenFrame = screenFrame }

    var isVisible: Bool { panel?.isVisible == true }

    func present(_ value: HoldPresentation?) {
        guard value != presentation else { return }
        presentation = value
        generation += 1
        let token = generation
        displayTask?.cancel()
        switch value {
        case let .holding(session):
            model.session = session
            model.completed = false
            model.animateExit = false
            model.visible = true
            if isVisible { return }
            // Filtering starts immediately; very brief accidental taps need no HUD flash.
            displayTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.showPanel()
            }
        case let .completed(session):
            guard isVisible, model.session == session else { hideNow(); return }
            model.completed = true
            displayTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.model.animateExit = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.model.visible = false
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, self.generation == token else { return }
                self.hideNow()
            }
        case nil:
            hideNow()
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        if let frame = screenFrame ?? screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.midY - 84))
        }
        panel.orderFrontRegardless()
    }

    private func hideNow() {
        model.animateExit = false
        model.visible = false
        panel?.orderOut(nil)
        model.session = nil
        displayTask = nil
    }

    private func makePanel() -> PassivePanel {
        let panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 168),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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

@MainActor
@Observable
final class HoldOverlayModel {
    var session: HoldSession?
    var completed = false
    var visible = false
    var animateExit = false
}
