import AppKit
import CoreGraphics
import QuitGuardCore

struct RuntimePolicy: Equatable, Sendable {
    var enabled: Bool
    var duration: Double
    var sessionActive: Bool
    var target: QuitTarget?
    var qKeyCodes: Set<UInt16>
    var unprotectedTarget: QuitTarget? = nil
}

enum ProtectionState: Equatable, Sendable {
    case starting
    case ready
    case paused
    case accessibilityRequired
    case postingPermissionRequired
    case secureInput
    case sessionInactive
    case recovering
    case connectionFailed(checkInputMonitoring: Bool)
    case selectionRequired

    var title: String {
        switch self {
        case .starting: "正在连接保护"
        case .ready: "防误触保护已开启"
        case .paused: "已手动暂停"
        case .accessibilityRequired: "需要\(PermissionSettingsDestination.deviceControl.title)授权"
        case .postingPermissionRequired: "退出按键发送待授权"
        case .secureInput: "安全输入期间暂停"
        case .sessionInactive: "当前会话已暂停"
        case .recovering: "正在恢复保护"
        case .connectionFailed: "保护尚未连接"
        case .selectionRequired: "请添加已保护应用"
        }
    }

    var detail: String {
        switch self {
        case .starting: "正在检查授权并连接键盘保护。"
        case .ready: "短按 ⌘Q 会被取消；按住至进度完成后，向当前应用发送正常退出请求。"
        case .paused: "⌘Q 按原有方式工作。重新启用后恢复长按保护。"
        case .accessibilityRequired: "请在系统设置的“\(PermissionSettingsDestination.deviceControl.title)”中允许 SlowQuitGuard，以便拦截 ⌘Q。授权后会自动检查。"
        case .postingPermissionRequired: "系统尚未允许发送退出快捷键。请检查“\(PermissionSettingsDestination.deviceControl.title)”授权；若开关已打开，请重新打开当前这份 App 后检查。"
        case .secureInput: "macOS 安全输入正在限制键盘监听。保护暂时不可用；安全输入结束后会自动检查并恢复。"
        case .sessionInactive: "睡眠或会话切换期间暂停保护，返回当前会话后自动检查并恢复。"
        case .recovering: "键盘监听已中断，正在自动重新连接。本次尚未完成的长按已取消，请恢复后重新按键。"
        case .connectionFailed: "暂时无法建立键盘保护，正在间隔重试。可检查权限，或点击“修复保护”。"
        case .selectionRequired: "当前使用白名单模式。请在“已保护应用”中添加要使用长按退出的应用。"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.shield"
        case .paused, .secureInput, .sessionInactive: "shield.slash"
        case .starting, .recovering: "arrow.triangle.2.circlepath"
        default: "exclamationmark.shield"
        }
    }
}

struct ServiceSnapshot: Equatable, Sendable {
    var revision: UInt64 = 0
    var state: ProtectionState = .starting
    var holdPresentation: HoldPresentation?
    var feedback: HoldFeedback?
    var lastShortcut: ShortcutDiagnostic?
    var accessibilityGranted = false
    var postingGranted = false
    var listeningGranted = false
    var tapEnabled = false
    var secureInput = false
    var recoveryCount = 0
    var lastRecoveryReason: String?
    var lastRecoveryDate: Date?
}

enum HoldPresentation: Equatable, Sendable {
    case holding(HoldSession)
    case completed(HoldSession)
    case failed(HoldSession, stoppedAt: Double)
}

enum PermissionStage: Equatable {
    case checking, accessibility, posting, inputMonitoring, ready
}

enum GuardSettingsTab: Hashable {
    case general, applications, sounds
}

enum CurrentApplication {
    static func target() -> QuitTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular, !app.isTerminated,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              bundleID != "com.apple.finder",
              let launchDate = app.launchDate else { return nil }
        return QuitTarget(
            identity: .init(processID: app.processIdentifier, bundleID: bundleID,
                            launchTime: launchDate.timeIntervalSince1970),
            name: app.localizedName ?? bundleID
        )
    }
}

extension KeyModifiers {
    init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskSecondaryFn) { insert(.function) }
    }
}
