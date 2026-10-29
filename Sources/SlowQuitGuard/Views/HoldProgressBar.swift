import AppKit
import QuartzCore
import QuitGuardCore
import SwiftUI

struct HoldProgressBar: NSViewRepresentable {
    let session: HoldSession?
    let completed: Bool

    func makeNSView(context: Context) -> HoldProgressTrack { HoldProgressTrack() }
    func updateNSView(_ view: HoldProgressTrack, context: Context) {
        view.configure(session: session, completed: completed)
    }
}

@MainActor
final class HoldProgressTrack: NSView {
    private let fill = CALayer()
    private var session: HoldSession?
    private var completed = false
    private var lastSize = CGSize.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.masksToBounds = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer?.addSublayer(fill)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("长按退出进度")
    }

    required init?(coder: NSCoder) { return nil }

    func configure(session: HoldSession?, completed: Bool) {
        guard session != self.session || completed != self.completed else { return }
        self.session = session
        self.completed = completed
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
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            fill.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }

    override func accessibilityValue() -> Any? {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        return NSNumber(value: completed ? 1 : session?.progress(at: now) ?? 0)
    }

    var displayedProgress: Double {
        Double((fill.presentation() ?? fill).transform.m11)
    }

    private func animateFromCurrentTime() {
        guard bounds.width > 0 else { return }
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        let progress = completed ? 1 : session?.progress(at: now) ?? 0
        let remaining = completed ? 0 : session?.remaining(at: now) ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateColors()
        fill.bounds = CGRect(origin: .zero, size: bounds.size)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        fill.removeAnimation(forKey: "holdProgress")
        fill.transform = CATransform3DMakeScale(session == nil ? 0 : 1, 1, 1)
        if remaining > 0 {
            let animation = CABasicAnimation(keyPath: "transform.scale.x")
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
