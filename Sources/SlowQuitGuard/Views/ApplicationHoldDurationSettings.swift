import AppKit
import QuitGuardCore
import SwiftUI

struct ApplicationHoldDurationSettings: View {
    let model: ProtectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: StoredApplication?
    @State private var invalidSelection = false

    var body: some View {
        Group {
            if let editing {
                ApplicationHoldDurationEditor(application: editing, globalDuration: model.holdDuration,
                    customDuration: model.customDuration(for: editing.bundleID)?.tenths,
                    cancel: { self.editing = nil }, save: { tenths in
                        model.saveDuration(tenths, for: editing)
                        self.editing = nil
                    })
            } else {
                applicationList
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }

    private var applicationList: some View {
        let durations = model.customApplicationDurations
        let names = Dictionary(grouping: durations, by: \.application.name)
        return VStack(alignment: .leading, spacing: 12) {
            Text("自定义时长").font(.title2).accessibilityAddTraits(.isHeader)
            if durations.isEmpty {
                ContentUnavailableView("暂无自定义时长", systemImage: "timer")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(durations) { item in
                            durationRow(item, showIdentifier: (names[item.application.name]?.count ?? 0) > 1)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }
            if invalidSelection {
                Text("所选应用无法配置长按保护。请选择其他 App。").foregroundStyle(.secondary)
            }
            HStack {
                Button("选择 App…") {
                    invalidSelection = false
                    model.chooseApplicationForDuration { application in
                        invalidSelection = application == nil
                        editing = application
                    }
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func durationRow(_ item: ApplicationHoldDuration, showIdentifier: Bool) -> some View {
        HStack(spacing: 10) {
            if let path = item.application.path {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable().scaledToFit().frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.application.name).lineLimit(1).truncationMode(.middle)
                if showIdentifier {
                    Text(item.id).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                if !model.enabled || !model.isProtected(item.id) {
                    Text("保护未启用").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ProtectionModel.durationLabel(item.duration)).monospacedDigit()
            Button("编辑…") { editing = item.application }
                .accessibilityLabel("编辑\(item.application.name)的时长")
        }
        .padding(.vertical, 3)
    }
}

private struct ApplicationHoldDurationEditor: View {
    let application: StoredApplication
    let globalDuration: Double
    let cancel: () -> Void
    let save: (Int?) -> Void
    @State private var usesCustomDuration: Bool
    @State private var tenths: Int

    init(application: StoredApplication, globalDuration: Double, customDuration: Int?,
         cancel: @escaping () -> Void, save: @escaping (Int?) -> Void) {
        self.application = application
        self.globalDuration = globalDuration
        self.cancel = cancel
        self.save = save
        // Seed the edit once. The draft is committed only by the Save button.
        _usesCustomDuration = State(initialValue: customDuration != nil)
        _tenths = State(initialValue: customDuration ?? Int((globalDuration * 10).rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(application.name).font(.title2).accessibilityAddTraits(.isHeader)
            Form {
                Picker("长按时长", selection: $usesCustomDuration) {
                    Text("使用全局时长").tag(false)
                    Text("自定义时长").tag(true)
                }
                if usesCustomDuration {
                    Slider(value: Binding(get: { Double(tenths) / 10 }, set: { tenths = Int(($0 * 10).rounded()) }),
                           in: HoldDuration.range, step: HoldDuration.step) {
                        Text(ProtectionModel.durationLabel(Double(tenths) / 10)).monospacedDigit()
                    } minimumValueLabel: {
                        Text("0.5 秒")
                    } maximumValueLabel: {
                        Text("3 秒")
                    }
                    .accessibilityLabel("按住时长")
                    .accessibilityValue(ProtectionModel.durationLabel(Double(tenths) / 10))
                } else {
                    LabeledContent("按住时长", value: ProtectionModel.durationLabel(globalDuration))
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("保存") { save(usesCustomDuration ? tenths : nil) }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
