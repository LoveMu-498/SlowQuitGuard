import AppKit
import QuitGuardCore
import SwiftUI

struct ApplicationRulesView: View {
    @Binding var mode: ApplicationProtectionRules.Mode
    let protectedApplications: [StoredApplication]
    let excludedApplications: [StoredApplication]
    let selectionMessage: String?
    let addApplications: (Bool) -> Void
    let setProtection: (Bool, String) -> Void
    let restoreDefault: (String) -> Void

    private var duplicateNames: Set<String> {
        let grouped = Dictionary(grouping: protectedApplications + excludedApplications, by: \.name)
        return Set(grouped.filter { $0.value.count > 1 }.keys)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("名单模式", selection: $mode) {
                Text("默认保护（黑名单）").tag(ApplicationProtectionRules.Mode.blacklist)
                Text("仅保护所选（白名单）").tag(ApplicationProtectionRules.Mode.whitelist)
            }
            .pickerStyle(.segmented)
            Text(mode == .blacklist
                 ? "默认保护所有应用；“已排除应用”中的 App 除外。未列出的应用也受保护。"
                 : "只保护“已保护应用”中的 App；其他应用按原来的方式退出。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                ruleColumn(title: "已保护应用", applications: protectedApplications, protected: true)
                ruleColumn(title: "已排除应用", applications: excludedApplications, protected: false)
            }
            if mode == .whitelist && protectedApplications.isEmpty {
                Label("白名单中尚无应用。添加后，才会对所选 App 启用长按退出。", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let selectionMessage { Text(selectionMessage).font(.callout).foregroundStyle(.secondary) }
            Text("名单会保存，与应用是否正在运行无关。排除应用后，本工具不拦截它的 ⌘Q。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func ruleColumn(title: String, applications: [StoredApplication], protected: Bool) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                if applications.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: protected ? "checkmark.shield" : "shield.slash").font(.title)
                        Text("尚未添加应用")
                        Text("使用下方按钮选择 App。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(applications) { app in
                                ApplicationRuleRow(application: app, protected: protected,
                                    showIdentifier: duplicateNames.contains(app.name),
                                    move: { setProtection(!protected, app.bundleID) },
                                    remove: { restoreDefault(app.bundleID) })
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Divider()
                Button("添加应用…") { addApplications(protected) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } label: {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(applications.count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ApplicationRuleRow: View {
    let application: StoredApplication
    let protected: Bool
    let showIdentifier: Bool
    let move: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let path = application.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
            } else {
                Image(systemName: "app").font(.title3).frame(width: 24).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(application.name).lineLimit(1).truncationMode(.middle)
                if showIdentifier {
                    Text(application.bundleID).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .help(application.path ?? application.bundleID)
            Spacer(minLength: 0)
            Button(action: move) { Image(systemName: protected ? "arrow.right" : "arrow.left") }
                .help(protected ? "移到已排除应用" : "移到已保护应用")
                .accessibilityLabel(protected ? "将\(application.name)移到已排除应用" : "将\(application.name)移到已保护应用")
            Button(action: remove) { Image(systemName: "xmark") }
                .help("移出名单，按当前模式的默认规则处理")
                .accessibilityLabel("将\(application.name)移出名单")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }
}
