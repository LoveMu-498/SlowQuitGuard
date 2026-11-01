import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemController {
    private(set) var status: SMAppService.Status
    private(set) var isChanging = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let readStatus: () -> SMAppService.Status
    @ObservationIgnored private let register: () throws -> Void
    @ObservationIgnored private let unregister: () async throws -> Void
    @ObservationIgnored private let openSettings: () -> Void

    init(readStatus: @escaping () -> SMAppService.Status,
         register: @escaping () throws -> Void,
         unregister: @escaping () async throws -> Void,
         openSettings: @escaping () -> Void) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.openSettings = openSettings
        status = readStatus()
    }

    var isEnabled: Bool {
        get { status == .enabled }
        set { Task { await setEnabled(newValue) } }
    }

    var detail: String {
        switch status {
        case .notRegistered, .notFound:
            "开启后，登录 Mac 时自动在菜单栏运行，并沿用上次的保护设置。"
        case .enabled:
            "登录 Mac 时自动在菜单栏运行，并沿用上次的保护设置。"
        case .requiresApproval:
            "自动启动尚未获系统允许。请在系统“登录项”中允许 SlowQuitGuard。"
        @unknown default:
            "无法确认自动启动状态。请打开系统“登录项”检查。"
        }
    }

    func refresh() {
        let latest = readStatus()
        if latest != status {
            status = latest
            errorMessage = nil
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        refresh()
        errorMessage = nil
        if enabled, status == .requiresApproval {
            openLoginItems()
            return
        }
        if enabled, status == .enabled { return }
        if !enabled, status == .notRegistered || status == .notFound { return }

        isChanging = true
        defer { isChanging = false }
        do {
            if enabled {
                try register()
            } else {
                try await unregister()
            }
            status = readStatus()
            if enabled, status == .notRegistered || status == .notFound {
                errorMessage = "系统尚未启用自动启动。请确认 App 仍在原位置，重新打开后再试，或打开系统“登录项”检查。"
            } else if !enabled, status == .enabled || status == .requiresApproval {
                errorMessage = "系统尚未移除登录项。请重试，或打开系统“登录项”检查。"
            }
        } catch {
            status = readStatus()
            // A concurrent system change may already have fulfilled this request.
            if enabled, status == .enabled || status == .requiresApproval { return }
            if !enabled, status == .notRegistered || status == .notFound { return }
            errorMessage = "未能\(enabled ? "开启" : "关闭")自动启动：\(error.localizedDescription)"
        }
    }

    func openLoginItems() { openSettings() }

    static func live() -> LoginItemController {
        LoginItemController(readStatus: { SMAppService.mainApp.status },
            register: { try SMAppService.mainApp.register() },
            unregister: { try await SMAppService.mainApp.unregister() },
            openSettings: { SMAppService.openSystemSettingsLoginItems() })
    }
}
