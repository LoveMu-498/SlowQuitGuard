import Foundation
import QuitGuardCore

enum PermissionSettingsDestination: String, CaseIterable {
    case deviceControl
    case inputMonitoring

    var title: String { title(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) }

    func title(macOSMajorVersion: Int) -> String {
        switch self {
        case .deviceControl: macOSMajorVersion >= 27 ? "设备控制和数据访问" : "辅助功能"
        case .inputMonitoring: "输入监控"
        }
    }

    var url: URL {
        let anchor = self == .deviceControl ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?" + anchor)!
    }
}

extension PermissionRequirement {
    var settingsDestination: PermissionSettingsDestination {
        switch self {
        case .accessibility, .eventPosting: .deviceControl
        case .inputMonitoring: .inputMonitoring
        }
    }

    var title: String {
        switch self {
        case .accessibility: "拦截退出快捷键"
        case .eventPosting: "发送退出快捷键"
        case .inputMonitoring: "输入监控"
        }
    }
}
