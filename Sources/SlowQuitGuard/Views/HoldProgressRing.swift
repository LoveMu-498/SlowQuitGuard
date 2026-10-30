import AppKit
import QuartzCore
import QuitGuardCore
import SwiftUI

struct HoldProgressRing: NSViewRepresentable {
    let session: HoldSession?
    let phase: HoldOverlayPhase
    let stoppedAt: Double?

    func makeNSView(context: Context) -> HoldRingTrack { HoldRingTrack() }
    func updateNSView(_ view: HoldRingTrack, context: Context) {
        view.configure(session: session, phase: phase, stoppedAt: stoppedAt)
    }
}

@MainActor
final class HoldRingTrack: NSView {
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private var session: HoldSession?
    private var phase: HoldOverlayPhase = .holding
    private var stoppedAt: Double?
    private var lastSize = CGSize.zero
    private let lineWidth: CGFloat = 10

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [track, fill] {
            shape.fillColor = NSColor.clear.cgColor
            shape.lineWidth = lineWidth
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("长按退出进度")
    }

    required init?(coder: NSCoder) { return nil }

    func configure(session: HoldSession?, phase: HoldOverlayPhase, stoppedAt: Double? = nil) {
        guard session != self.session || phase != self.phase || stoppedAt != self.stoppedAt else { return }
        self.session = session
        self.phase = phase
        self.stoppedAt = stoppedAt
        animateFromCurrentTime()
    }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        animateFromCurrentTime()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateColors()
        CATransaction.commit()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            track.strokeColor = NSColor.labelColor.withAlphaComponent(contrast ? 0.38 : 0.14).cgColor
            let color: NSColor = phase == .completed ? .systemGreen : (phase == .failed ? .systemOrange : .systemBlue)
            fill.strokeColor = color.cgColor
        }
    }

    override func accessibilityValue() -> Any? {
        NSNumber(value: phase == .completed ? 1 : session?.progress(at: stoppedAt ?? Self.now) ?? 0)
    }

    var displayedProgress: Double { Double((fill.presentation() ?? fill).strokeEnd) }
    private static var now: Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

    private func animateFromCurrentTime() {
        guard bounds.width > lineWidth, bounds.height > lineWidth else { return }
        let now = Self.now
        let progress = phase == .completed ? 1 : session?.progress(at: stoppedAt ?? now) ?? 0
        let remaining = phase == .holding ? session?.remaining(at: now) ?? 0 : 0
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY),
            radius: (min(bounds.width, bounds.height) - lineWidth) / 2,
            startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateColors()
        for shape in [track, fill] { shape.frame = bounds; shape.path = path }
        fill.removeAnimation(forKey: "holdProgress")
        fill.strokeEnd = remaining > 0 ? 1 : progress
        if remaining > 0 {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = progress
            animation.toValue = 1
            animation.duration = remaining
            animation.beginTime = fill.convertTime(CACurrentMediaTime(), from: nil)
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            fill.add(animation, forKey: "holdProgress")
        }
        CATransaction.commit()
    }
}
