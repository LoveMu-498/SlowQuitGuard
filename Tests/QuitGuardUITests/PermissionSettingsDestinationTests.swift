import Foundation
import QuitGuardCore
import Testing
@testable import SlowQuitGuard

@Test func inputMonitoringUsesItsOwnSystemSettingsPage() {
    let device = PermissionRequirement.accessibility.settingsDestination
    let posting = PermissionRequirement.eventPosting.settingsDestination
    let monitoring = PermissionRequirement.inputMonitoring.settingsDestination
    #expect(device == posting)
    #expect(device.url.query == "Privacy_Accessibility")
    #expect(monitoring.url.query == "Privacy_ListenEvent")
    #expect(monitoring.url != device.url)
    #expect(device.url.scheme == "x-apple.systempreferences")
}

@Test func permissionNamesMatchTheRunningMacOSGeneration() {
    #expect(PermissionSettingsDestination.deviceControl.title(macOSMajorVersion: 26) == "辅助功能")
    #expect(PermissionSettingsDestination.deviceControl.title(macOSMajorVersion: 27) == "设备控制和数据访问")
    #expect(PermissionSettingsDestination.inputMonitoring.title(macOSMajorVersion: 27) == "输入监控")
}
