import SwiftUI

struct GuardSettingsView: View {
    @Bindable var model: ProtectionModel

    var body: some View {
        TabView(selection: $model.settingsTab) {
            generalSettings
                .tabItem { Label("通用", systemImage: "slider.horizontal.3") }
                .tag(GuardSettingsTab.general)
            applicationSettings
                .tabItem { Label("应用保护", systemImage: "checkmark.square") }
                .tag(GuardSettingsTab.applications)
        }
        .frame(minWidth: 680, idealWidth: 840, minHeight: 500, idealHeight: 620)
        .background(SettingsWindowAnchor(presenter: model.settingsWindow).frame(width: 0, height: 0))
    }

    private var generalSettings: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.displayState.symbol)
                        .font(.system(size: 28))
                        .foregroundStyle(model.displayState == .ready ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.displayState.title).font(.headline)
                        Text(model.displayState.detail)
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                permissionAction
            } header: {
                Text("SlowQuitGuard")
            }

            Section("长按退出") {
                Toggle("启用防误触保护", isOn: $model.enabled)
                LabeledContent("按住时长", value: model.durationLabel)
                Slider(value: $model.holdDuration, in: 0.5...3, step: 0.1) {
                    Text("按住时长")
                } minimumValueLabel: { Text("0.5 秒") }
                  maximumValueLabel: { Text("3 秒") }
                Text("松开 ⌘ 或 Q、按下其他键，或切换应用，都会取消本次长按。应用仍可提示保存，或由你取消退出。")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Button("修复保护", action: model.repairProtection)
                    .disabled(!model.enabled)
                Text("⌘Q 表现异常时使用。取消本次长按，检查权限并重新连接键盘监听；不改变应用名单。")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("连接详情") {
                    LabeledContent("拦截退出快捷键", value: model.snapshot.accessibilityGranted ? "已授权" : "未授权")
                    LabeledContent("发送退出快捷键", value: model.snapshot.postingGranted ? "已允许" : "未允许")
                    LabeledContent("监听连接", value: model.snapshot.tapEnabled ? "已连接" : "未连接")
                    LabeledContent("安全输入", value: model.snapshot.secureInput ? "已开启" : "未开启")
                    LabeledContent("恢复次数", value: "\(model.snapshot.recoveryCount)")
                    if let reason = model.snapshot.lastRecoveryReason {
                        LabeledContent("最近恢复", value: reason)
                    }
                }
            }
            Text("仅保护键盘 ⌘Q。菜单退出、Dock 退出和强制退出仍按系统原有方式工作。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var applicationSettings: some View {
        ApplicationRulesView(mode: $model.protectionMode,
            protectedApplications: model.protectedApplications, excludedApplications: model.excludedApplications,
            selectionMessage: model.applicationSelectionMessage,
            addApplications: model.chooseApplications,
            setProtection: { model.setProtection($0, for: $1) }, restoreDefault: model.restoreDefault)
    }

    @ViewBuilder private var permissionAction: some View {
        switch model.displayState {
        case .accessibilityRequired:
            Button("前往\(PermissionSettingsDestination.deviceControl.title)…", action: model.requestAccessibility)
                .buttonStyle(.borderedProminent)
        case .postingPermissionRequired:
            Button("检查退出按键发送…", action: model.requestPostingPermission)
                .buttonStyle(.borderedProminent)
        case .connectionFailed(checkInputMonitoring: true):
            Button("检查输入监控权限…", action: model.requestInputMonitoring)
        default:
            EmptyView()
        }
    }
}
