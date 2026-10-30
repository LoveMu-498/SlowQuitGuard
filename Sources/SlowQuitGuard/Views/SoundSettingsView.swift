import QuitGuardCore
import SwiftUI

struct SoundSettingsView: View {
    @Binding var preferences: FeedbackPreferences
    let preview: (FeedbackSoundPreference) -> Void

    var body: some View {
        Form {
            ForEach(HoldFeedbackKind.allCases, id: \.self) { kind in
                Section {
                    Toggle("播放提示音", isOn: binding(kind, \.enabled))
                    Picker("声音", selection: binding(kind, \.tone)) {
                        ForEach(FeedbackTone.allCases, id: \.self) { tone in
                            Text(tone.title).tag(tone)
                        }
                    }
                    HStack(spacing: 12) {
                        Slider(value: binding(kind, \.volume), in: 0...1) { Text("音量") }
                        Text(preferences[kind].volume.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit().frame(width: 46, alignment: .trailing)
                        Button("试听") { preview(preferences[kind]) }
                            .disabled(preferences[kind].volume == 0)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(kind.title + "音量和试听")
                } header: {
                    Text(kind.title)
                } footer: {
                    Text(kind.detail)
                }
            }
            Text("音量只调整本工具的提示音，不改变系统音量。声音不会循环播放；后台自动恢复保持静音。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func binding<Value>(_ kind: HoldFeedbackKind, _ keyPath: WritableKeyPath<FeedbackSoundPreference, Value>) -> Binding<Value> {
        Binding(get: { preferences[kind][keyPath: keyPath] }, set: { value in
            var item = preferences[kind]
            item[keyPath: keyPath] = value
            preferences[kind] = item
        })
    }
}

extension FeedbackTone {
    var title: String {
        switch self {
        case .softRise: "柔和双音"
        case .softTap: "轻触"
        case .lowDouble: "低音提醒"
        }
    }
}

extension HoldFeedbackKind {
    var title: String {
        switch self {
        case .success: "退出请求已发送"
        case .cancellation: "长按已取消"
        case .failure: "本次操作中断"
        }
    }

    var detail: String {
        switch self {
        case .success: "长按完成并发送退出快捷键时播放。应用仍可能显示保存提示，或由你取消退出。"
        case .cancellation: "提前松开按键、按下其他键或切换应用，取消当前长按时播放。"
        case .failure: "进行中的长按遇到权限或监听异常，或未能发送退出请求时播放。普通取消不使用这项声音。"
        }
    }
}
