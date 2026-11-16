import QuitGuardCore
import SwiftUI

struct SoundSettingsView: View {
    @Binding var preferences: FeedbackPreferences
    let preview: (FeedbackSoundPreference) -> Void
    let previewEncouragement: () -> Void
    let previewDurationCue: (HoldDurationRelation) -> Void

    var body: some View {
        Form {
            Section {
                Toggle("激励模式", isOn: $preferences.encouragementEnabled)
                    .accessibilityHint("持续按住 Command 和 Q 时播放轻柔渐强的进度提示音")
                SoundVolumeControls(volume: $preferences.encouragementVolume, title: "激励提示音",
                    defaultVolume: FeedbackPreferences.defaultEncouragementVolume,
                    preview: previewEncouragement, reset: { preferences.resetEncouragementVolume() })
            } header: {
                Text("长按进度")
            } footer: {
                Text("按住 ⌘Q 时，提示音持续上扬并渐强。")
            }
            Section("时长差异提示") {
                Toggle("播放时长差异提示音", isOn: $preferences.durationCueEnabled)
                    .accessibilityHint("本次长按时长比全局时长短或长时播放")
                SoundVolumeControls(volume: $preferences.durationCueVolume, title: "时长差异提示音",
                    defaultVolume: FeedbackPreferences.defaultDurationCueVolume,
                    preview: nil, reset: { preferences.durationCueVolume = FeedbackPreferences.defaultDurationCueVolume })
                HStack {
                    Button("试听较短时长") { previewDurationCue(.shorter) }
                    Button("试听较长时长") { previewDurationCue(.longer) }
                }
                .disabled(preferences.durationCueVolume == 0)
            }
            ForEach(HoldFeedbackKind.allCases, id: \.self) { kind in
                Section {
                    Toggle("播放提示音", isOn: binding(kind, \.enabled))
                        .accessibilityLabel(kind.title + "提示音开关")
                    Picker("声音", selection: binding(kind, \.tone)) {
                        ForEach(FeedbackTone.allCases, id: \.self) { tone in
                            Text(tone.title).tag(tone)
                        }
                    }
                    .accessibilityLabel(kind.title + "提示音声音")
                    SoundVolumeControls(volume: binding(kind, \.volume), title: kind.title + "提示音",
                        defaultVolume: FeedbackPreferences()[kind].volume,
                        preview: { preview(preferences[kind]) }, reset: { preferences.resetVolume(for: kind) })
                } header: {
                    Text(kind.title)
                }
            }
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

private struct SoundVolumeControls: View {
    @Binding var volume: Double
    let title: String
    let defaultVolume: Double
    let preview: (() -> Void)?
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $volume, in: 0...1) { Text("音量") }
                .accessibilityLabel(title + "音量")
                .accessibilityValue(volume.formatted(.percent.precision(.fractionLength(0))))
            Text(volume.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit().frame(width: 46, alignment: .trailing)
            if let preview {
                Button("试听", action: preview)
                    .disabled(volume == 0)
                    .accessibilityLabel("试听" + title)
            }
            Button("恢复默认", action: reset)
                .disabled(volume == defaultVolume)
                .help("默认音量：" + defaultVolume.formatted(.percent.precision(.fractionLength(0))))
                .accessibilityLabel("恢复" + title + "默认音量")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title + "音量和试听")
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

}
