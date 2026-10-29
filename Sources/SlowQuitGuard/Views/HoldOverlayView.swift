import QuitGuardCore
import SwiftUI

struct HoldOverlayView: View {
    let model: HoldOverlayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.completed ? "checkmark.circle" : "command.circle")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(model.completed ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.completed ? "已发送退出请求" : "按住 ⌘Q 退出").font(.headline)
                    Text(model.session?.target.name ?? "").font(.callout).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HoldProgressBar(session: model.session, completed: model.completed)
                .frame(height: 6)
            HStack {
                Text(model.completed ? "正在交给应用处理" : "松开 ⌘ 或 Q 可取消")
                Spacer(minLength: 8)
                if let session = model.session, !model.completed {
                    RemainingHoldTime(session: session)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360, height: 168)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : 4)
        .animation(model.animateExit ? .easeOut(duration: 0.1) : nil, value: model.visible)
    }
}

private struct RemainingHoldTime: View {
    let session: HoldSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
            Text("剩余 " + session.remaining(at: now).formatted(.number.precision(.fractionLength(1))) + " 秒")
                .monospacedDigit()
        }
    }
}
