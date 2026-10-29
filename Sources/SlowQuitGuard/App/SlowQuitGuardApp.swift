import AppKit
import SwiftUI

@main
struct SlowQuitGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            GuardMenu(model: delegate.model)
        } label: {
            GuardStatusIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            GuardSettingsView(model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ProtectionModel()
    private var permissionGuide: PermissionGuideController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            _ = other.activate(from: .current, options: [])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        permissionGuide = PermissionGuideController(model: model)
        model.permissions.onPresentGuide = { [weak self] in self?.permissionGuide?.show() }
        model.start()
        model.checkPermissionsOnOpen()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.checkPermissionsOnOpen()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.permissions.onPresentGuide = nil
        model.stop()
        permissionGuide?.close()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if model.permissions.guideVisible { model.permissions.refresh() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
