import SwiftUI

struct ApplicationsChecklistView: View {
    let applications: [RunningApplicationItem]
    let isProtected: (String) -> Bool
    let setProtection: (Bool, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("勾选：使用本工具的长按 ⌘Q 保护。\n取消勾选：使用应用原来的退出方式。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Chrome 已开启自身退出提醒时，可取消勾选 Chrome，避免出现两层提醒。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if applications.isEmpty {
                ContentUnavailableView("暂无可配置的应用", systemImage: "app.dashed", description: Text("启动一个应用后，会在这里显示。"))
            } else {
                ForEach(applications) { app in
                    HStack(spacing: 10) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                        }
                        Toggle(app.name, isOn: Binding(
                            get: { isProtected(app.bundleID) },
                            set: { setProtection($0, app.bundleID) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}
