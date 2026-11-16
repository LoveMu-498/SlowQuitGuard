import AppKit
import QuitGuardCore

@MainActor
final class FeedbackSoundService {
    private var lastSequence: UInt64 = 0
    private var nextAllowedTime = -Double.infinity
    private var lastPlayedKind: HoldFeedbackKind?
    private let playSound: (FeedbackTone, Double) -> Void
    private let stopSound: () -> Void
    private let playEncouragement: (Double, Double, Double) -> Void
    private let setEncouragementVolume: (Double) -> Void
    private let stopEncouragement: () -> Void
    private let playDurationCue: (HoldDurationRelation, Double, @escaping () -> Void) -> Bool
    private let stopDurationCue: () -> Void
    private let now: () -> Double
    private var durationCueSession: HoldSession?
    private var encouragementVolume = 0.0
    private var encouragementSession: HoldSession?
    private var latestHoldSession: HoldSession?
    private var finishedSession: HoldSession?

    init(playSound: @escaping (FeedbackTone, Double) -> Void, stopSound: @escaping () -> Void = {},
         playEncouragement: @escaping (Double, Double, Double) -> Void = { _, _, _ in },
         setEncouragementVolume: @escaping (Double) -> Void = { _ in },
         stopEncouragement: @escaping () -> Void = {},
         playDurationCue: @escaping (HoldDurationRelation, Double, @escaping () -> Void) -> Bool = { _, _, _ in false },
         stopDurationCue: @escaping () -> Void = {},
         now: @escaping () -> Double = { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }) {
        self.playSound = playSound
        self.stopSound = stopSound
        self.playEncouragement = playEncouragement
        self.setEncouragementVolume = setEncouragementVolume
        self.stopEncouragement = stopEncouragement
        self.playDurationCue = playDurationCue
        self.stopDurationCue = stopDurationCue
        self.now = now
    }

    static func live() -> FeedbackSoundService {
        let player = NativeFeedbackSoundPlayer()
        return FeedbackSoundService(playSound: { player.play($0, volume: $1) }, stopSound: { player.stop() },
            playEncouragement: { player.playEncouragement(duration: $0, elapsed: $1, volume: $2) },
            setEncouragementVolume: { player.setEncouragementVolume($0) },
            stopEncouragement: { player.stopEncouragement() },
            playDurationCue: { player.playDurationCue($0, volume: $1, completion: $2) },
            stopDurationCue: { player.stopDurationCue() })
    }

    func updateHold(_ presentation: HoldPresentation?, enabled: Bool, volume: Double, now: Double,
                    durationCueVolume: Double = 0) {
        let previousHold = latestHoldSession
        if case let .holding(session) = presentation { latestHoldSession = session }
        encouragementVolume = enabled ? volume : 0
        setEncouragementVolume(volume)
        guard case let .holding(session) = presentation,
              session != finishedSession,
              now >= session.startedAt, now < session.startedAt + session.duration else {
            endDurationCue()
            endEncouragement()
            return
        }
        if previousHold != session {
            endDurationCue()
            if durationCueVolume > 0, session.durationRelation != .standard {
                endEncouragement()
                stopSound()
                durationCueSession = session
                let started = playDurationCue(session.durationRelation, durationCueVolume) { [weak self] in
                    self?.durationCueFinished(for: session)
                }
                if started { return }
                durationCueSession = nil
            }
        }
        if durationCueVolume == 0 { endDurationCue() }
        startEncouragement(for: session, now: now)
    }

    private func startEncouragement(for session: HoldSession, now: Double) {
        guard encouragementVolume > 0, now >= session.startedAt, now < session.startedAt + session.duration else {
            endEncouragement()
            return
        }
        guard durationCueSession == nil else { return }
        guard encouragementSession != session else { return }
        endEncouragement()
        stopSound()
        encouragementSession = session
        playEncouragement(session.duration, now - session.startedAt, encouragementVolume)
    }

    private func durationCueFinished(for session: HoldSession) {
        guard durationCueSession == session else { return }
        durationCueSession = nil
        startEncouragement(for: session, now: now())
    }

    func handle(_ event: HoldFeedback?, preferences: FeedbackPreferences, now: Double) {
        guard let event, event.sequence > lastSequence else { return }
        lastSequence = event.sequence
        // Snapshots retain the previous outcome. A newer hold owns the audio now,
        // even when its encouragement is muted or disabled.
        if let latestHoldSession, latestHoldSession != event.session,
           latestHoldSession.startedAt >= event.session.startedAt { return }
        finishedSession = event.session
        endDurationCue()
        endEncouragement()
        let preference = preferences[event.kind]
        guard preference.enabled, preference.volume > 0,
              now >= event.occurredAt, now - event.occurredAt <= 1,
              now >= nextAllowedTime || (event.kind == .failure && lastPlayedKind != .failure) else { return }
        playSound(preference.tone, preference.volume)
        lastPlayedKind = event.kind
        nextAllowedTime = now + (event.kind == .failure ? 0.5 : 0.15)
    }

    func preview(_ preference: FeedbackSoundPreference) {
        guard encouragementSession == nil, durationCueSession == nil else { return }
        guard preference.volume > 0 else { return }
        stopEncouragement()
        playSound(preference.tone, preference.volume)
    }

    func previewEncouragement(duration: Double, volume: Double) {
        guard encouragementSession == nil, durationCueSession == nil, volume > 0 else { return }
        stopSound()
        stopEncouragement()
        playEncouragement(duration, 0, volume)
    }

    func previewDurationCue(_ relation: HoldDurationRelation, volume: Double) {
        guard encouragementSession == nil, durationCueSession == nil, volume > 0 else { return }
        stopSound()
        stopEncouragement()
        _ = playDurationCue(relation, volume) {}
    }

    func stop() {
        encouragementSession = nil
        endDurationCue()
        stopEncouragement()
        stopSound()
    }

    private func endDurationCue() {
        guard durationCueSession != nil else { return }
        durationCueSession = nil
        stopDurationCue()
    }

    private func endEncouragement() {
        guard encouragementSession != nil else { return }
        stopEncouragement()
        encouragementSession = nil
    }
}

@MainActor
private final class NativeFeedbackSoundPlayer: NSObject, NSSoundDelegate {
    private var currentSound: NSSound?
    private var encouragementSound: NSSound?
    private var durationSound: NSSound?
    private var durationSoundCompletion: (() -> Void)?

    func play(_ tone: FeedbackTone, volume: Double) {
        stopEncouragement()
        stopDurationCue()
        guard let url = Bundle.main.url(forResource: tone.resourceName, withExtension: "wav", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        currentSound?.stop()
        sound.volume = Float(volume)
        currentSound = sound
        sound.play()
    }

    func stop() {
        currentSound?.stop()
        currentSound = nil
        stopDurationCue()
    }

    func playDurationCue(_ relation: HoldDurationRelation, volume: Double, completion: @escaping () -> Void) -> Bool {
        stop()
        stopEncouragement()
        guard let data = HoldDurationCue.waveData(for: relation), let sound = NSSound(data: data) else { return false }
        sound.volume = Float(volume)
        sound.delegate = self
        durationSound = sound
        durationSoundCompletion = completion
        guard sound.play() else {
            stopDurationCue()
            return false
        }
        return true
    }

    func stopDurationCue() {
        durationSound?.delegate = nil
        durationSound?.stop()
        durationSound = nil
        durationSoundCompletion = nil
    }

    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        let identity = ObjectIdentifier(sound)
        Task { @MainActor [weak self] in
            guard let self, let current = self.durationSound, ObjectIdentifier(current) == identity else { return }
            let completion = self.durationSoundCompletion
            self.stopDurationCue()
            completion?()
        }
    }

    func playEncouragement(duration: Double, elapsed: Double, volume: Double) {
        stop()
        stopEncouragement()
        let preparationStarted = ProcessInfo.processInfo.systemUptime
        guard let sound = NSSound(data: EncouragementCue.waveData(duration: duration)) else { return }
        let offset = elapsed + ProcessInfo.processInfo.systemUptime - preparationStarted
        guard offset >= 0, offset < duration else { return }
        sound.volume = Float(volume)
        sound.loops = false
        sound.currentTime = offset
        encouragementSound = sound
        sound.play()
    }

    func setEncouragementVolume(_ volume: Double) { encouragementSound?.volume = Float(volume) }

    func stopEncouragement() { encouragementSound?.stop(); encouragementSound = nil }
}
