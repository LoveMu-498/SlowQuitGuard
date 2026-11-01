import AppKit
import CoreGraphics
import QuartzCore
import QuitGuardCore
import SwiftUI
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct HoldOverlayVisualTests {
    private var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }
    private func session(name: String = "Google Chrome", duration: Double = 1, elapsed: Double = 0) -> HoldSession {
        .init(target: .init(identity: .init(processID: 123, bundleID: "com.google.Chrome"), name: name),
              keyCode: 12, startedAt: now - elapsed, duration: duration)
    }

    @Test func anInterruptedRingFreezesInsteadOfReachingSuccess() async throws {
        _ = NSApplication.shared
        let ring = HoldRingTrack(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        let window = OverlayPreviewPanel(contentRect: NSRect(x: -10000, y: -10000, width: 96, height: 96),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = ring
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let hold = session(duration: 1)
        ring.configure(session: hold, phase: .failed, stoppedAt: hold.startedAt + 0.35)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(150))
        #expect(abs(ring.displayedProgress - 0.35) < 0.001)
        try await Task.sleep(for: .milliseconds(150))
        #expect(abs(ring.displayedProgress - 0.35) < 0.001)
    }

    @Test func terminalConfirmationSurvivesTargetClosureAndCannotHideTheNextHold() async throws {
        _ = NSApplication.shared
        let overlay = HoldOverlayController(screenFrame: NSRect(x: -10000, y: -10000, width: 600, height: 400))
        defer { overlay.dismissImmediately() }
        let first = session()
        overlay.present(.holding(first))
        try await Task.sleep(for: .milliseconds(120))
        overlay.present(.completed(first))
        overlay.present(nil)
        try await Task.sleep(for: .milliseconds(120))
        #expect(overlay.isVisible)
        let host = overlay.hostingView
        overlay.present(.holding(session(name: "文本编辑")))
        try await Task.sleep(for: .milliseconds(250))
        #expect(overlay.isVisible)
        #expect(overlay.hostingView === host)
    }

    @Test func fullApplicationNamesGetMoreHeightWithoutChangingTheRingWidth() {
        _ = NSApplication.shared
        let short = model(name: "Google Chrome")
        let long = model(name: "这是用于核对完整应用名称换行的较长应用名称，不应被省略号截断")
        let shortSize = NSHostingView(rootView: HoldOverlayView(model: short)).fittingSize
        let longSize = NSHostingView(rootView: HoldOverlayView(model: long)).fittingSize
        #expect(shortSize.width == 408)
        #expect(longSize.width == shortSize.width)
        #expect(longSize.height > shortSize.height)
        #expect(shortSize.height >= 146)
    }

    @Test func nativeOverlayStatesAndSoundControlsRenderWithoutKeyboardOrPlayback() async throws {
        _ = NSApplication.shared
        for (label, phase) in [("holding", HoldOverlayPhase.holding), ("completed", .completed), ("failed", .failed)] {
            for dark in [false, true] {
                let value = model(name: "Google Chrome", phase: phase)
                try await render(HoldOverlayView(model: value),
                    name: "island-\(label)-\(dark ? "dark" : "light")-0.4.1", dark: dark)
            }
        }
        try await render(HoldOverlayView(model: model(name: "Google Chrome"), reduceTransparencyOverride: true),
            name: "island-reduced-transparency-0.4.1")
        try await render(HoldOverlayView(model: model(name: "这是用于核对完整应用名称换行的较长应用名称，不应被省略号截断")),
            name: "island-long-name-0.4.1")
        try await render(SoundSettingsView(preferences: .constant(.init()), preview: { _ in }),
            size: NSSize(width: 840, height: 620), name: "sound-settings-light-0.4.1")
        for reason in [ShortcutReason.unprotectedApplication, .releasedEarly, .listenerInterrupted, .requestSent] {
            var snapshot = ServiceSnapshot()
            snapshot.state = .ready
            snapshot.tapEnabled = true
            snapshot.lastShortcut = .init(reason: reason, occurredAt: Date(), applicationName: "Google Chrome")
            try await render(Form {
                ProtectionDiagnosticsView(report: .init(version: "0.4.1", state: .ready,
                    snapshot: snapshot, mode: "默认保护（黑名单）"), copy: { _ in })
            }.formStyle(.grouped), size: NSSize(width: 840, height: 360), name: "shortcut-" + reason.rawValue + "-0.4.1")
        }
        var quiet = FeedbackPreferences()
        quiet.cancellation.enabled = false
        quiet.failure.volume = 0
        try await render(SoundSettingsView(preferences: .constant(quiet), preview: { _ in }),
            size: NSSize(width: 840, height: 620), name: "sound-settings-dark-0.4.1", dark: true)
    }

    private func model(name: String, phase: HoldOverlayPhase = .holding) -> HoldOverlayModel {
        let value = HoldOverlayModel()
        value.session = session(name: name, duration: 3, elapsed: phase == .completed ? 3 : 1.5)
        value.phase = phase
        value.stoppedAt = phase == .failed ? value.session!.startedAt + 1.65 : nil
        value.visible = true
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            value.targetIcon = NSWorkspace.shared.icon(forFile: url.path)
        }
        return value
    }

    private func render<V: View>(_ view: V, size: NSSize? = nil, name: String, dark: Bool = false) async throws {
        let nativeCapture = ProcessInfo.processInfo.environment["SLOWQUITGUARD_CAPTURE_NATIVE"] == "1"
        if nativeCapture { try #require(CGPreflightScreenCaptureAccess(), "Existing capture access is required; this test never requests it") }
        let hosted = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.controlActiveState, .key))
        let chosenSize = size ?? hosted.fittingSize
        hosted.sizingOptions = []
        hosted.frame = NSRect(origin: .zero, size: chosenSize)
        hosted.autoresizingMask = [.width, .height]
        let background = OverlayPreviewBackground(frame: hosted.frame)
        background.addSubview(hosted)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = nativeCapture ? NSPoint(x: screen.maxX - chosenSize.width - 32, y: screen.maxY - chosenSize.height - 48)
                                   : NSPoint(x: -10000, y: -10000)
        let window = OverlayPreviewPanel(contentRect: NSRect(origin: origin, size: chosenSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = nativeCapture ? .screenSaver : .floating
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        var documentWindow: OverlayPreviewPanel?
        if nativeCapture && size == nil {
            // Known backdrops inside and behind the owned window keep
            // material samples independent of the user's desktop.
            let document = OverlayPreviewPanel(contentRect: NSRect(origin: origin, size: chosenSize).insetBy(dx: -40, dy: -40),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            document.level = window.level
            document.ignoresMouseEvents = true
            document.appearance = window.appearance
            document.contentView = OverlayDocumentBackdrop(frame: NSRect(origin: .zero, size: document.frame.size))
            document.orderFrontRegardless()
            documentWindow = document
            let captureBackdrop = OverlayDocumentBackdrop(frame: hosted.frame)
            captureBackdrop.addSubview(hosted)
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.hasShadow = false
            window.contentView = captureBackdrop
        } else { window.contentView = background }
        window.setContentSize(chosenSize)
        window.orderFrontRegardless()
        defer { window.orderOut(nil); documentWindow?.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(120))
        hosted.layoutSubtreeIfNeeded()
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/ui-previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if nativeCapture {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // Capture only the owned window; notifications or other apps must
            // never appear in documentation screenshots.
            let prefix = size == nil ? "native-context-" : "native-"
            process.arguments = ["-x", "-o", "-l\(window.windowNumber)",
                output.appendingPathComponent(prefix + name + ".png").path]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            return
        }
        let bitmap = try #require(background.bitmapImageRepForCachingDisplay(in: background.bounds))
        background.cacheDisplay(in: background.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent(name + ".png"))
    }
}

private final class OverlayPreviewBackground: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private final class OverlayDocumentBackdrop: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        for index in 0..<10 {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSRect(x: 25, y: 24 + index * 24, width: Int(bounds.width) - 50, height: 4).fill()
        }
        NSColor.systemBlue.withAlphaComponent(0.25).setFill()
        NSRect(x: bounds.width * 0.68, y: 0, width: 18, height: bounds.height).fill()
    }
}

private final class OverlayPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
