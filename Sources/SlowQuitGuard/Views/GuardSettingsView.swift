import QuitGuardCore
import SwiftUI

struct GuardSettingsView: View {
    @Bindable var model: ProtectionModel
    @State private var showsApplicationDurations = false

    var body: some View {
        TabView(selection: $model.settingsTab) {
            generalSettings
                .tabItem { Label("通用", systemImage: "slider.horizontal.3") }
                .tag(GuardSettingsTab.general)
            applicationSettings
                .tabItem { Label("应用保护", systemImage: "checkmark.square") }
                .tag(GuardSettingsTab.applications)
            SoundSettingsView(preferences: Binding(get: { model.soundSettings.preferences },
                set: model.updateSoundPreferences), preview: model.previewSound,
                previewEncouragement: model.previewEncouragement, previewDurationCue: model.previewDurationCue)
                .tabItem { Label("声音", systemImage: "speaker.wave.2") }
                .tag(GuardSettingsTab.sounds)
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

            LoginItemSettingsSection(controller: model.loginItem)

            Section("长按退出") {
                Toggle("启用防误触保护", isOn: $model.enabled)
                Slider(value: $model.holdDuration, in: HoldDuration.range, step: HoldDuration.step) {
                    Text("全局时长 " + model.durationLabel)
                } minimumValueLabel: { Text("0.5 秒") }
                  maximumValueLabel: { Text("3 秒") }
                .accessibilityLabel("全局时长")
                .accessibilityValue(model.durationLabel)
                Text("松开按键或切换应用可取消长按。")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Button("修复保护", action: model.repairProtection)
                    .disabled(!model.enabled)
                    .help("重新连接键盘保护")
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
            ProtectionDiagnosticsView(report: .init(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建",
                state: model.displayState, snapshot: model.snapshot,
                mode: model.protectionMode == .blacklist ? "默认保护（黑名单）" : "仅保护所选（白名单）"))
            Text("仅保护键盘 ⌘Q，菜单和 Dock 退出不受影响。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var applicationSettings: some View {
        ApplicationRulesView(mode: $model.protectionMode,
            protectedApplications: model.protectedApplications, excludedApplications: model.excludedApplications,
            selectionMessage: model.applicationSelectionMessage,
            addApplications: model.chooseApplications,
            setProtection: { model.setProtection($0, for: $1) }, restoreDefault: model.restoreDefault,
            manageDurations: { showsApplicationDurations = true })
            .sheet(isPresented: $showsApplicationDurations) {
                ApplicationHoldDurationSettings(model: model)
            }
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
