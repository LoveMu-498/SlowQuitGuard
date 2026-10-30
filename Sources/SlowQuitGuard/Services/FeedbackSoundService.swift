import AppKit
import QuitGuardCore

@MainActor
final class FeedbackSoundService {
    private var lastSequence: UInt64 = 0
    private var nextAllowedTime = -Double.infinity
    private var lastPlayedKind: HoldFeedbackKind?
    private let playSound: (FeedbackTone, Double) -> Void
    private let stopSound: () -> Void

    init(playSound: @escaping (FeedbackTone, Double) -> Void, stopSound: @escaping () -> Void = {}) {
        self.playSound = playSound
        self.stopSound = stopSound
    }

    static func live() -> FeedbackSoundService {
        let player = NativeFeedbackSoundPlayer()
        return FeedbackSoundService(playSound: { player.play($0, volume: $1) }, stopSound: { player.stop() })
    }

    func handle(_ event: HoldFeedback?, preferences: FeedbackPreferences, now: Double) {
        guard let event, event.sequence > lastSequence else { return }
        lastSequence = event.sequence
        let preference = preferences[event.kind]
        guard preference.enabled, preference.volume > 0,
              now >= event.occurredAt, now - event.occurredAt <= 1,
              now >= nextAllowedTime || (event.kind == .failure && lastPlayedKind != .failure) else { return }
        playSound(preference.tone, preference.volume)
        lastPlayedKind = event.kind
        nextAllowedTime = now + (event.kind == .failure ? 0.5 : 0.15)
    }

    func preview(_ preference: FeedbackSoundPreference) {
        guard preference.volume > 0 else { return }
        playSound(preference.tone, preference.volume)
    }

    func stop() { stopSound() }
}

@MainActor
private final class NativeFeedbackSoundPlayer {
    private var currentSound: NSSound?

    func play(_ tone: FeedbackTone, volume: Double) {
        guard let url = Bundle.main.url(forResource: tone.resourceName, withExtension: "wav", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        currentSound?.stop()
        sound.volume = Float(volume)
        currentSound = sound
        sound.play()
    }

    func stop() { currentSound?.stop(); currentSound = nil }
}
