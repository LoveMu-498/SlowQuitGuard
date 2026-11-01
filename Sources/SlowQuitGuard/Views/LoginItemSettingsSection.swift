import SwiftUI

struct LoginItemSettingsSection: View {
    @Bindable var controller: LoginItemController

    var body: some View {
        Section("启动") {
            Toggle("登录时自动启动", isOn: $controller.isEnabled)
                .disabled(controller.isChanging)
                .help("登录 Mac 时自动打开 SlowQuitGuard。")
            Text(controller.detail)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = controller.errorMessage {
                Text(error)
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("打开系统登录项…", action: controller.openLoginItems)
                if controller.status == .requiresApproval {
                    Button("移除登录项") {
                        Task { await controller.setEnabled(false) }
                    }
                }
            }
            .disabled(controller.isChanging)
        }
        .onAppear(perform: controller.refresh)
    }
}
