import AppKit
import SwiftUI

struct ProtectionDiagnosticsView: View {
    let report: ProtectionDiagnosticReport
    var copy: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    @State private var copied = false

    var body: some View {
        Section {
            if let last = report.snapshot.lastShortcut {
                LabeledContent("最近一次 ⌘Q", value: last.occurredAt.formatted(date: .omitted, time: .standard))
                if let name = last.applicationName { LabeledContent("应用", value: name) }
                Text(last.reason.title).font(.headline)
                Text(last.reason.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("还没有记录到 ⌘Q")
                Text("保护连接后，使用一次 ⌘Q 即可查看处理结果。保护未连接时，可能无法检测按键。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("复制诊断信息") { copy(report.text); copied = true }
                if copied { Text("已复制").font(.callout).foregroundStyle(.secondary) }
            }
            Text("只保留最近一次处理结果，退出本工具后清除。复制内容包含保护状态和处理原因，不包含应用名称或键入内容。")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } header: { Text("⌘Q 处理结果") }
        .onChange(of: report.snapshot.lastShortcut) { copied = false }
    }
}
