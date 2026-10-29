import AppKit
import SwiftUI

@MainActor
final class PermissionGuideController: NSObject, NSWindowDelegate {
    private let model: ProtectionModel
    private var window: NSWindow?

    init(model: ProtectionModel) { self.model = model; super.init() }

    func show() {
        if window == nil {
            let hosted = NSHostingController(rootView: LivePermissionGuide(model: model, close: { [weak self] in self?.close() }))
            let window = NSWindow(contentViewController: hosted)
            window.styleMask = [.titled, .closable]
            window.title = "SlowQuitGuard"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            Self.fitContent(of: window)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            if let window = self?.window { Self.fitContent(of: window) }
        }
    }

    static func fitContent(of window: NSWindow) {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let height = ceil(content.fittingSize.height)
        guard height > 0 else { return }
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: PermissionGuideView.width, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
    }

    func close() { window?.close() }
    func windowWillClose(_ notification: Notification) { model.permissions.guideDidClose() }
}

private struct LivePermissionGuide: View {
    let model: ProtectionModel
    let close: () -> Void

    var body: some View {
        PermissionGuideView(stage: model.permissionStage, protectionPaused: !model.enabled,
            openSettings: model.permissions.openSettings, checkAndContinue: model.permissions.checkAndContinue,
            close: close, access: model.permissions.access, lastCheckStillMissing: model.permissions.lastCheckStillMissing)
    }
}
