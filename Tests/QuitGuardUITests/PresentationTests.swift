import AppKit
import QuartzCore
import QuitGuardCore
import SwiftUI
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct PresentationTests {
    private static var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
    private static let target = QuitTarget(identity: .init(processID: 123, bundleID: "test.editor"), name: "文本编辑")

    @Test func continuousProgressUsesPresentationFramesAndDoesNotRestart() async throws {
        _ = NSApplication.shared
        let track = HoldProgressTrack(frame: NSRect(x: 0, y: 0, width: 320, height: 6))
        let window = PreviewPanel(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 6),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = track
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let session = HoldSession(target: Self.target, keyCode: 12, startedAt: Self.now, duration: 2)
        track.configure(session: session, completed: false)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(150))
        let first = track.displayedProgress
        track.configure(session: session, completed: false)
        try await Task.sleep(for: .milliseconds(200))
        let second = track.displayedProgress
        #expect(first > 0 && first < 0.5)
        #expect(second > first && second < 0.8)
        track.configure(session: session, completed: true)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(40))
        #expect(abs(track.displayedProgress - 1) < 0.001)
        try saveJSON(["first": first, "second": second, "completed": track.displayedProgress], name: "progress-samples.json")
    }

    @Test func overlayReusesTheHostAndShowsTheCompletedFrame() async throws {
        _ = NSApplication.shared
        let overlay = HoldOverlayController(screenFrame: NSRect(x: -10000, y: -10000, width: 600, height: 400))
        defer { overlay.present(nil) }
        let first = HoldSession(target: Self.target, keyCode: 12, startedAt: Self.now, duration: 2)
        overlay.present(.holding(first))
        try await Task.sleep(for: .milliseconds(150))
        #expect(overlay.isVisible)
        let initialHost = try #require(overlay.hostingView)
        overlay.present(.holding(first))
        #expect(overlay.hostingView === initialHost)
        overlay.present(.completed(first))
        #expect(overlay.isVisible)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!overlay.isVisible)
        let next = HoldSession(target: Self.target, keyCode: 12, startedAt: Self.now, duration: 1)
        overlay.present(.holding(next))
        try await Task.sleep(for: .milliseconds(150))
        #expect(overlay.isVisible)
        #expect(overlay.hostingView === initialHost)
    }

    @Test func quickCancelledPressNeverFlashesTheOverlay() async throws {
        _ = NSApplication.shared
        let overlay = HoldOverlayController(screenFrame: NSRect(x: -10000, y: -10000, width: 600, height: 400))
        let session = HoldSession(target: Self.target, keyCode: 12, startedAt: Self.now, duration: 1)
        overlay.present(.holding(session))
        overlay.present(nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!overlay.isVisible)
        #expect(overlay.hostingView == nil)
    }

    @Test func permissionAndApplicationScreensRenderWithoutStartingProtection() async throws {
        _ = NSApplication.shared
        for (name, stage) in [("permission-checking", PermissionStage.checking), ("permission-required", .accessibility),
                              ("permission-posting", .posting), ("permission-input", .inputMonitoring), ("permission-ready", .ready)] {
            let access = PermissionAccess(accessibility: stage != .accessibility,
                eventPosting: stage == .ready || stage == .inputMonitoring,
                inputMonitoring: stage == .ready, inputMonitoringRequired: stage == .inputMonitoring)
            try await render(PermissionGuideView(stage: stage, protectionPaused: false, openSettings: { _ in },
                checkAndContinue: {}, close: {}, access: access),
                size: permissionSize(stage: stage, access: access), name: name + "-0.3.1")
        }
        let protected = [StoredApplication(bundleID: "test.editor", name: "文本编辑", path: nil)]
        let excluded = [StoredApplication(bundleID: "com.google.Chrome", name: "Google Chrome", path: nil)]
        for mode in ApplicationProtectionRules.Mode.allCases {
            try await render(ApplicationRulesView(mode: .constant(mode), protectedApplications: protected,
                excludedApplications: excluded, selectionMessage: nil, addApplications: { _ in },
                setProtection: { _, _ in }, restoreDefault: { _ in }),
                size: NSSize(width: 840, height: 540), name: "application-rules-" + mode.rawValue + "-0.3.0")
        }
        try await render(ApplicationRulesView(mode: .constant(.whitelist), protectedApplications: [],
            excludedApplications: [], selectionMessage: nil, addApplications: { _ in },
            setProtection: { _, _ in }, restoreDefault: { _ in }),
            size: NSSize(width: 840, height: 540), name: "application-rules-empty-0.3.0")
        let duplicateApplications = [
            StoredApplication(bundleID: "example.chat.personal", name: "微信", path: nil),
            StoredApplication(bundleID: "example.chat.work", name: "微信", path: nil),
            StoredApplication(bundleID: "example.editor", name: "文本编辑与一个名称较长的应用", path: nil)]
        try await render(ApplicationRulesView(mode: .constant(.blacklist), protectedApplications: duplicateApplications,
            excludedApplications: excluded, selectionMessage: nil, addApplications: { _ in },
            setProtection: { _, _ in }, restoreDefault: { _ in }),
            size: NSSize(width: 680, height: 430), name: "application-rules-compact-dark-0.3.0", dark: true)
        try await render(PermissionGuideView(stage: .posting, protectionPaused: false, openSettings: { _ in },
            checkAndContinue: {}, close: {}, access: .init(accessibility: true, eventPosting: false, inputMonitoring: false),
            lastCheckStillMissing: true), size: permissionSize(stage: .posting,
                access: .init(accessibility: true, eventPosting: false, inputMonitoring: false), missing: true),
            name: "permission-check-dark-0.3.1", dark: true)
    }

    @Test func permissionWindowFitsEveryStateWithoutAFixedHeight() throws {
        _ = NSApplication.shared
        for stage in [PermissionStage.checking, .accessibility, .posting, .inputMonitoring, .ready] {
            let access = PermissionAccess(accessibility: stage != .accessibility,
                eventPosting: stage == .ready || stage == .inputMonitoring,
                inputMonitoring: stage == .ready, inputMonitoringRequired: stage == .inputMonitoring)
            let hosted = NSHostingController(rootView: PermissionGuideView(stage: stage, protectionPaused: false,
                openSettings: { _ in }, checkAndContinue: {}, close: {}, access: access,
                lastCheckStillMissing: stage == .posting))
            let window = PreviewPanel(contentViewController: hosted)
            defer { window.close() }
            PermissionGuideController.fitContent(of: window)
            let content = try #require(window.contentView)
            #expect(content.frame.width == PermissionGuideView.width)
            #expect(content.frame.height >= 280 && content.frame.height < 500)
            #expect(abs(content.frame.height - ceil(content.fittingSize.height)) < 1)
        }
    }

    private func permissionSize(stage: PermissionStage, access: PermissionAccess, missing: Bool = false) -> NSSize {
        let view = PermissionGuideView(stage: stage, protectionPaused: false, openSettings: { _ in },
            checkAndContinue: {}, close: {}, access: access, lastCheckStillMissing: missing)
        let hosted = NSHostingView(rootView: view)
        let size = hosted.fittingSize
        return NSSize(width: PermissionGuideView.width, height: ceil(size.height))
    }

    private var output: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/ui-previews")
    }

    private func saveJSON(_ values: [String: Double], name: String) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name))
    }

    private func render<V: View>(_ view: V, size: NSSize, name: String, dark: Bool = false) async throws {
        let hosted = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light).environment(\.controlActiveState, .key))
        hosted.sizingOptions = []
        hosted.frame = NSRect(origin: .zero, size: size)
        hosted.autoresizingMask = [.width, .height]
        let backdrop = PreviewBackdrop(frame: hosted.frame)
        backdrop.addSubview(hosted)
        let window = PreviewPanel(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = backdrop
        window.setContentSize(size)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(120))
        hosted.layoutSubtreeIfNeeded()
        let bitmap = try #require(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent(name + ".png"))
    }
}

private final class PreviewBackdrop: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
