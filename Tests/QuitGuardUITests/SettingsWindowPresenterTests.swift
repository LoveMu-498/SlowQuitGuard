import AppKit
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct SettingsWindowPresenterTests {
    @Test func delayedWindowCreationDoesNotLoseTheFrontingRequest() async throws {
        _ = NSApplication.shared
        var activations = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activations += 1 })
        var opens = 0
        presenter.open { opens += 1 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(opens == 1)
        #expect(activations == 0)
        let window = FrontingProbeWindow()
        presenter.register(window)
        try await Task.sleep(for: .milliseconds(20))
        #expect(activations == 1)
        #expect(window.frontingRequests == 1)
    }

    @Test func settingsAreBroughtForwardAfterMenuTrackingEnds() async throws {
        _ = NSApplication.shared
        var activations = 0
        let presenter = SettingsWindowPresenter(activateApplication: { activations += 1 })
        let window = FrontingProbeWindow()
        presenter.register(window)
        presenter.menuDidBegin()
        presenter.open {}
        try await Task.sleep(for: .milliseconds(20))
        #expect(activations == 0)
        presenter.menuDidClose()
        try await Task.sleep(for: .milliseconds(20))
        #expect(activations == 1)
        #expect(window.frontingRequests == 1)
        #expect(window.regardlessRequests == 1)
    }
}

private final class FrontingProbeWindow: NSWindow {
    var frontingRequests = 0
    var regardlessRequests = 0
    override func makeKeyAndOrderFront(_ sender: Any?) { frontingRequests += 1 }
    override func orderFrontRegardless() { regardlessRequests += 1 }
}
