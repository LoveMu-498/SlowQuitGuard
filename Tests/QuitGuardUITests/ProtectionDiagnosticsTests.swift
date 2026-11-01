import AppKit
import QuitGuardCore
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct ProtectionDiagnosticsTests {
    @Test func runtimePermissionsUpdateWithoutReadingSystemAPIsOrReconnecting() {
        var reads = 0
        var reconnects = 0
        let coordinator = PermissionCoordinator(readAccess: {
            reads += 1
            return .init(accessibility: false, eventPosting: false, inputMonitoring: false)
        }, requestAccess: { _ in }, openSettings: { _ in })
        coordinator.onRefreshProtection = { reconnects += 1 }
        coordinator.acceptRuntimeAccess(.init(accessibility: true, eventPosting: true, inputMonitoring: false),
                                        inputMonitoringRequired: false)
        coordinator.acceptRuntimeAccess(.init(accessibility: true, eventPosting: true, inputMonitoring: false),
                                        inputMonitoringRequired: false)
        #expect(coordinator.stage == .ready)
        #expect(reads == 0)
        #expect(reconnects == 0)
        coordinator.acceptRuntimeAccess(.init(accessibility: true, eventPosting: true, inputMonitoring: false),
                                        inputMonitoringRequired: true)
        #expect(coordinator.stage == .inputMonitoring)
        coordinator.checkAndContinue()
        #expect(reads == 1)
        #expect(coordinator.stage == .accessibility)
    }

    @Test func copiedDiagnosticsExplainTheOutcomeWithoutExposingTheApplicationName() {
        var snapshot = ServiceSnapshot()
        snapshot.lastShortcut = .init(reason: .releasedEarly, occurredAt: Date(timeIntervalSince1970: 100),
                                      applicationName: "用户的私有应用名称")
        snapshot.state = .ready
        snapshot.tapEnabled = true
        let report = ProtectionDiagnosticReport(version: "0.4.1", state: .ready, snapshot: snapshot,
                                                mode: "默认保护（黑名单）")
        #expect(report.text.contains("没有发送退出请求"))
        #expect(report.text.contains("最近一次 ⌘Q"))
        #expect(!report.text.contains("用户的私有应用名称"))
        #expect(!report.text.contains("org.slowquitguard."))
        #expect(report.text.contains("已连接"))
    }

    @Test func theTargetWindowTakesPriorityOverThePointerAndSpanningWindowsUseTheLargerArea() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        #expect(OverlayScreenPlacement.screenIndex(window: CGRect(x: 1550, y: 50, width: 900, height: 700),
                    screens: screens, pointer: CGPoint(x: 50, y: 50)) == 1)
        #expect(OverlayScreenPlacement.screenIndex(window: CGRect(x: 1200, y: 50, width: 900, height: 700),
                    screens: screens, pointer: CGPoint(x: 50, y: 50)) == 1)
        #expect(OverlayScreenPlacement.screenIndex(window: nil, screens: screens, pointer: CGPoint(x: 50, y: 50)) == 0)
        #expect(OverlayScreenPlacement.screenIndex(window: .null, screens: [], pointer: .zero) == nil)
    }

    @Test func quartzCoordinatesConvertAboveAndLeftOfThePrimaryScreen() {
        #expect(OverlayScreenPlacement.appKitRect(fromQuartz: CGRect(x: -1000, y: -800, width: 800, height: 600),
            primaryTop: 900) == CGRect(x: -1000, y: 1100, width: 800, height: 600))
    }

    @Test func warmUpIsHiddenAndOneHoldKeepsItsScreenThroughCompletion() {
        _ = NSApplication.shared
        var resolutions = 0
        let targetFrame = NSRect(x: -10000, y: -10000, width: 1400, height: 900)
        let overlay = HoldOverlayController(screenForTarget: { _ in resolutions += 1; return targetFrame })
        defer { overlay.dismissImmediately() }
        overlay.warmUp()
        #expect(!overlay.isVisible)
        let host = overlay.hostingView
        let session = HoldSession(target: .init(identity: .init(processID: 123, bundleID: "test.editor"), name: "编辑器"),
            keyCode: 12, startedAt: Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000, duration: 1)
        overlay.present(.holding(session))
        #expect(overlay.isVisible)
        #expect(overlay.hostingView === host)
        #expect(overlay.displayedFrame?.midX == targetFrame.midX)
        #expect(overlay.displayedFrame?.midY == targetFrame.midY)
        overlay.present(.completed(session))
        #expect(resolutions == 1)
        #expect(overlay.displayedFrame?.midX == targetFrame.midX)
    }
}
