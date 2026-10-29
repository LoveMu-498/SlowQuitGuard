import SwiftUI
import QuitGuardCore

struct PermissionGuideView: View {
    let stage: PermissionStage
    let protectionPaused: Bool
    let openSettings: (PermissionRequirement) -> Void
    let checkAndContinue: () -> Void
    let close: () -> Void
    let access: PermissionAccess
    var lastCheckStillMissing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ready: Bool { stage == .ready }
    static let width: CGFloat = 540

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: ready ? "checkmark.shield" : "hand.raised")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(ready ? Color.green : Color.accentColor)
                    .symbolEffect(.pulse, options: .repeat(3), isActive: !ready && !reduceMotion)
                    .id(ready)
                    .transition(.modifier(active: PermissionIconPhase(scale: 0.25, opacity: 0, blur: 4),
                                          identity: PermissionIconPhase(scale: 1, opacity: 1, blur: 0)))
                    .frame(width: 40, height: 44)
                    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: ready)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(ready ? "权限已就绪" : "设置退出保护所需权限")
                        .font(.title2.weight(.semibold))
                    Text(description).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(PermissionRequirement.allCases, id: \.self) { requirement in
                        if requirement != .accessibility { Divider() }
                        permissionRow(requirement)
                    }
                }
                .padding(.horizontal, 6)
            }
            Text("前两项共用“\(PermissionSettingsDestination.deviceControl.title)”页面；输入监控使用独立页面。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if lastCheckStillMissing && !ready {
                Label("尚未检测到授权。请确认对应页面中 SlowQuitGuard 的开关已打开，再重新检查。", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stage == .posting {
                Text("如果开关已经打开，系统仍未允许发送按键，请退出并重新打开当前这份 App，再检查权限。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if ready {
                    Button("重新检查", action: checkAndContinue)
                    Spacer()
                    Button("完成", action: close)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("暂不授权", action: close).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("我已授权，重新检查", action: checkAndContinue)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(stage == .checking)
                }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var description: String {
        switch stage {
        case .checking: "正在检查系统权限。"
        case .accessibility: "在对应设置页面打开 SlowQuitGuard 的开关，授权后会自动检查。"
        case .posting: "拦截权限已通过，发送退出快捷键尚未通过。请检查下方对应项。"
        case .inputMonitoring: "当前键盘连接需要输入监控，请打开该项设置进行授权。"
        case .ready: protectionPaused ? "保护目前已手动暂停，可从菜单栏重新开启。" : "所需权限检查已通过，连接状态可在菜单栏查看。"
        }
    }

    private func permissionRow(_ requirement: PermissionRequirement) -> some View {
        let granted = access.isGranted(requirement)
        let required = access.isRequired(requirement)
        let status = stage == .checking ? "检查中" : (granted ? "已允许" : "未授权")
        return HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : (required ? "circle" : "minus.circle"))
                .font(.body).frame(width: 20)
                .foregroundStyle(granted ? Color.green : (required ? .accentColor : .secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(requirement.title).font(.headline)
                Text(requirement == .inputMonitoring
                     ? (!required && !granted ? "当前连接无需授权" : "用于接收键盘事件")
                     : requirement.settingsDestination.title)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(status).font(.caption).foregroundStyle(.secondary).fixedSize()
            Button("打开设置…") { openSettings(requirement) }
                .help("系统设置 → 隐私与安全 → " + requirement.settingsDestination.title)
                .accessibilityLabel("打开\(requirement.settingsDestination.title)：\(requirement.title)")
                .disabled(stage == .checking)
        }
        .padding(.vertical, 12)
    }
}

private struct PermissionIconPhase: ViewModifier {
    let scale: Double
    let opacity: Double
    let blur: Double
    func body(content: Content) -> some View {
        content.scaleEffect(scale).opacity(opacity).blur(radius: blur)
    }
}
