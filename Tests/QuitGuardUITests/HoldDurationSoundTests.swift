import AppKit
import QuitGuardCore
import Testing
@testable import SlowQuitGuard

@MainActor
struct HoldDurationSoundTests {
    private let target = QuitTarget(identity: .init(processID: 99, bundleID: "test.duration.editor"), name: "Editor")

    @Test func progressStartsAtActualElapsedTimeAfterTheOpeningCue() throws {
        let session = HoldSession(target: target, keyCode: 12, startedAt: 10, duration: 2.5, globalDuration: 1)
        var completion: (() -> Void)?
        var actions: [String] = []
        var elapsed: Double?
        let service = FeedbackSoundService(playSound: { _, _ in actions.append("outcome") },
            playEncouragement: { _, offset, _ in elapsed = offset; actions.append("progress") },
            stopEncouragement: { actions.append("stop progress") },
            playDurationCue: { relation, volume, finished in
                #expect(relation == .longer)
                #expect(volume == 0.12)
                actions.append("cue")
                completion = finished
                return true
            }, now: { 10.24 })

        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10, durationCueVolume: 0.12)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10.1, durationCueVolume: 0.12)
        #expect(actions == ["cue"])
        let finish = try #require(completion)
        finish()
        #expect(abs((elapsed ?? 0) - 0.24) < 0.0001)
        service.updateHold(.completed(session), enabled: true, volume: 0.12, now: 12.5, durationCueVolume: 0.12)
        service.handle(.init(sequence: 1, kind: .success, session: session, occurredAt: 12.5),
            preferences: .init(), now: 12.5)
        #expect(actions == ["cue", "progress", "stop progress", "outcome"])
    }

    @Test func cancellationSilencesTheWarningAndIgnoresItsLateCompletion() throws {
        let session = HoldSession(target: target, keyCode: 12, startedAt: 10, duration: 0.6, globalDuration: 1)
        var completion: (() -> Void)?
        var actions: [String] = []
        let service = FeedbackSoundService(playSound: { _, _ in actions.append("outcome") },
            playEncouragement: { _, _, _ in actions.append("progress") },
            playDurationCue: { relation, _, finished in
                #expect(relation == .shorter)
                actions.append("cue")
                completion = finished
                return true
            }, stopDurationCue: { actions.append("stop cue") }, now: { 10.15 })

        service.updateHold(.holding(session), enabled: false, volume: 0.12, now: 10, durationCueVolume: 0.12)
        service.updateHold(nil, enabled: true, volume: 0.12, now: 10.04, durationCueVolume: 0.12)
        service.handle(.init(sequence: 1, kind: .cancellation, session: session, occurredAt: 10.04),
            preferences: .init(), now: 10.04)
        let finish = try #require(completion)
        finish()
        #expect(actions == ["cue", "stop cue", "outcome"])
    }

    @Test func cuesDecodeInNativeAudioAndAreDistinct() throws {
        let shorter = try #require(HoldDurationCue.waveData(for: .shorter))
        let longer = try #require(HoldDurationCue.waveData(for: .longer))
        let warning = try #require(NSSound(data: shorter))
        let encourage = try #require(NSSound(data: longer))
        #expect(warning.duration > 0 && warning.duration < encourage.duration)
        #expect(encourage.duration < 0.5)
        #expect(HoldDurationCue.waveData(for: .standard) == nil)
    }
}
