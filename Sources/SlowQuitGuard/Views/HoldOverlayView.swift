import AppKit
import QuitGuardCore
import SwiftUI

struct HoldOverlayView: View {
    let model: HoldOverlayModel
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                HoldProgressRing(session: model.session, phase: model.phase, stoppedAt: model.stoppedAt)
                if model.phase == .completed {
                    Image(systemName: "checkmark").font(.system(size: 35, weight: .semibold))
                        .foregroundStyle(.green).accessibilityHidden(true)
                } else if model.phase == .failed {
                    Image(systemName: "exclamationmark").font(.system(size: 35, weight: .semibold))
                        .foregroundStyle(.orange).accessibilityHidden(true)
                } else if let icon = model.targetIcon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 42, height: 42)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "app.fill").font(.system(size: 36))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.session?.target.name ?? "")
                    .font(.system(size: 23, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if model.phase == .completed {
                    Text("已发送退出请求").font(.system(size: 16, weight: .medium))
                } else if model.phase == .failed {
                    Text("保护已中断").font(.system(size: 16, weight: .medium)).foregroundStyle(.orange)
                    Text("请松开快捷键后重试").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    if let session = model.session { RemainingHoldTime(session: session) }
                    Text("松开 ⌘ 或 Q 可取消").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 11)
        .frame(width: HoldOverlayLayout.width)
        .frame(minHeight: HoldOverlayLayout.minimumHeight)
        .modifier(GuardGlassSurface(reduceTransparency: reduceTransparencyOverride ?? reduceTransparency))
        .padding(HoldOverlayLayout.shadowInset)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible ? 0 : 4)
        .animation(model.animateExit ? .easeOut(duration: 0.1) : nil, value: model.visible)
    }
}

enum HoldOverlayLayout {
    static let width: CGFloat = 380
    static let minimumHeight: CGFloat = 118
    static let shadowInset: CGFloat = 14
    static let panelWidth = width + 2 * shadowInset
    static let minimumPanelHeight = minimumHeight + 2 * shadowInset
}

private struct GuardGlassSurface: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: Capsule())
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

private struct RemainingHoldTime: View {
    let session: HoldSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { _ in
            let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
            (Text("按住 ⌘Q · ") +
             Text("剩余 " + session.remaining(at: now).formatted(.number.precision(.fractionLength(1))) + " 秒")
                .foregroundColor(.blue))
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
