import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter {
    private weak var window: NSWindow?
    private var wantsFront = false
    private var menuDepth = 0
    private let activateApplication: () -> Void

    init(activateApplication: @escaping () -> Void = { NSApp.unhide(nil); NSApp.activate() }) {
        self.activateApplication = activateApplication
    }

    func open(using openSettings: () -> Void) {
        wantsFront = true
        openSettings()
        // SwiftUI may create its Settings window after the menu action returns.
        DispatchQueue.main.async { [weak self] in self?.bringForwardIfRequested() }
    }

    func register(_ window: NSWindow) {
        self.window = window
        window.collectionBehavior.remove(.canJoinAllSpaces)
        window.collectionBehavior.insert(.moveToActiveSpace)
        DispatchQueue.main.async { [weak self] in self?.bringForwardIfRequested() }
    }

    func menuDidClose() {
        menuDepth = max(0, menuDepth - 1)
        DispatchQueue.main.async { [weak self] in self?.bringForwardIfRequested() }
    }

    func menuDidBegin() { menuDepth += 1 }

    private func bringForwardIfRequested() {
        guard wantsFront, menuDepth == 0, let window else { return }
        activateApplication()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        wantsFront = false
    }
}

struct SettingsWindowAnchor: NSViewRepresentable {
    let presenter: SettingsWindowPresenter

    func makeNSView(context: Context) -> SettingsAnchorView {
        SettingsAnchorView(presenter: presenter)
    }

    func updateNSView(_ nsView: SettingsAnchorView, context: Context) {}
}

final class SettingsAnchorView: NSView {
    private let presenter: SettingsWindowPresenter

    init(presenter: SettingsWindowPresenter) {
        self.presenter = presenter
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { presenter.register(window) }
    }
}
