import AppKit
import SwiftUI

struct GuardMenu: View {
    @Bindable var model: ProtectionModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        menuContents.onAppear { model.prepareMenu() }
    }

    @ViewBuilder private var menuContents: some View {
        Text(model.displayState.title)
        if case .ready = model.displayState {
            if model.currentAppExcluded {
                Text("当前应用不启用长按保护")
            } else {
                Text("按住 ⌘Q " + model.durationLabel + "退出")
            }
        }
        Divider()
        Toggle("启用防误触保护", isOn: $model.enabled)

        switch model.displayState {
        case .accessibilityRequired:
            Button("授权\(PermissionSettingsDestination.deviceControl.title)…", action: model.requestAccessibility)
        case .postingPermissionRequired:
            Button("检查退出按键发送…", action: model.requestPostingPermission)
        case .connectionFailed(checkInputMonitoring: true):
            Button("检查输入监控权限…", action: model.requestInputMonitoring)
        default:
            EmptyView()
        }

        Divider()
        if let app = model.menuTarget {
            Text((model.menuTargetIsPrevious ? "上一个应用：" : "当前应用：") + String(app.name.prefix(18)))
            Toggle("为此应用开启防误触保护", isOn: protectionBinding(app.identity.bundleID))
            if !model.isProtected(app.identity.bundleID) {
                Text("⌘Q 交给应用原有功能处理")
            }
        }
        Menu("正在运行的应用") {
            Text("勾选表示使用本工具保护")
            Divider()
            ForEach(model.runningApplications) { app in
                Toggle(String(app.name.prefix(26)), isOn: protectionBinding(app.bundleID))
            }
            if model.runningApplications.isEmpty { Text("暂无可配置的运行中应用") }
            Divider()
            Button("管理应用名单…", action: showApplicationSettings)
        }
        Button("应用保护设置…", action: showApplicationSettings)
        Divider()
        Button("修复保护", action: model.repairProtection)
            .disabled(!model.enabled)
            .help("检查权限并重新连接键盘监听，不改变应用名单。")
        Button("设置…") { showSettings(tab: model.settingsTab) }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("退出 SlowQuitGuard") { NSApp.terminate(nil) }
    }

    private func protectionBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(get: { model.isProtected(bundleID) }, set: { model.setProtection($0, for: bundleID) })
    }

    private func showApplicationSettings() {
        showSettings(tab: .applications)
    }

    private func showSettings(tab: GuardSettingsTab) {
        model.settingsTab = tab
        model.settingsWindow.open { openSettings() }
    }
}
