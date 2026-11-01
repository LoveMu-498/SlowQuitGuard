import Foundation

enum ShortcutReason: String, CaseIterable, Sendable {
    case unprotectedApplication, releasedEarly, anotherKey, applicationChanged
    case protectionPaused, sessionPaused, settingsChanged, repairRequested
    case permissionRequired, secureInput, listenerInterrupted, requestNotSent, requestSent

    var title: String {
        switch self {
        case .unprotectedApplication: "由应用处理 ⌘Q"
        case .releasedEarly, .anotherKey, .applicationChanged, .protectionPaused,
             .sessionPaused, .settingsChanged, .repairRequested: "本次长按已取消"
        case .permissionRequired, .secureInput, .listenerInterrupted, .requestNotSent: "本次保护未能完成"
        case .requestSent: "退出请求已发送"
        }
    }

    var detail: String {
        switch self {
        case .unprotectedApplication: "此应用未开启本工具保护。⌘Q 按应用原来的方式处理。"
        case .releasedEarly: "你在时间结束前松开了按键。本工具没有发送退出请求。"
        case .anotherKey: "你按下了其他键。本工具已取消长按，没有发送退出请求。"
        case .applicationChanged: "你切换了应用。本工具已取消长按，没有发送退出请求。"
        case .protectionPaused: "保护已暂停。本工具没有发送这次退出请求。"
        case .sessionPaused: "电脑进入睡眠或切换了会话。本工具已取消长按，请返回后重新按住 ⌘Q。"
        case .settingsChanged: "保护设置已改变。本工具已取消长按，请重新按住 ⌘Q。"
        case .repairRequested: "你选择了修复保护。本工具已取消长按，正在检查权限并重新连接。"
        case .permissionRequired: "所需权限当前不可用。本工具没有发送退出请求，请检查权限。"
        case .secureInput: "macOS 正在限制键盘监听。本工具已取消长按，请在保护恢复后重试。"
        case .listenerInterrupted: "键盘监听已断开。本工具已取消长按，正在尝试恢复保护。"
        case .requestNotSent: "退出请求未能发送。请松开快捷键，检查保护状态后重试。"
        case .requestSent: "本工具已向应用发送退出请求。应用仍可能提示保存，或由你取消退出。"
        }
    }
}

struct ShortcutDiagnostic: Equatable, Sendable {
    let reason: ShortcutReason
    let occurredAt: Date
    let applicationName: String?
}

struct ProtectionDiagnosticReport {
    let version: String
    let state: ProtectionState
    let snapshot: ServiceSnapshot
    let mode: String

    var text: String {
        var lines = ["SlowQuitGuard \(version)", "保护状态：\(state.title)", "名单模式：\(mode)",
            "拦截退出快捷键：\(snapshot.accessibilityGranted ? "已授权" : "未授权")",
            "发送退出快捷键：\(snapshot.postingGranted ? "已允许" : "未允许")",
            "键盘监听：\(snapshot.tapEnabled ? "已连接" : "未连接")",
            "安全输入：\(snapshot.secureInput ? "已开启" : "未开启")",
            "恢复次数：\(snapshot.recoveryCount)"]
        if let reason = snapshot.lastRecoveryReason { lines.append("最近恢复：\(reason)") }
        if let last = snapshot.lastShortcut {
            lines += ["最近一次 ⌘Q：\(last.occurredAt.formatted(date: .numeric, time: .standard))",
                      "处理结果：\(last.reason.title)", "说明：\(last.reason.detail)"]
        } else { lines.append("最近一次 ⌘Q：尚未记录") }
        return lines.joined(separator: "\n")
    }
}
