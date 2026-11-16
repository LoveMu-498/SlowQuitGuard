import AppKit
import Foundation
import QuitGuardCore
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct EncouragementSoundTests {
    private var session: HoldSession {
        .init(target: .init(identity: .init(processID: 99, bundleID: "test.editor"), name: "编辑器"),
              keyCode: 12, startedAt: 10, duration: 1.5)
    }

    @Test func defaultOffAndNonHoldingStatesNeverStartProgressSound() {
        var plays = 0
        let service = FeedbackSoundService(playSound: { _, _ in }, playEncouragement: { _, _, _ in plays += 1 })
        service.updateHold(.holding(session), enabled: FeedbackPreferences().encouragementEnabled, volume: 0.12, now: 10)
        service.updateHold(nil, enabled: true, volume: 0.12, now: 10)
        service.updateHold(.completed(session), enabled: true, volume: 0.12, now: 11.5)
        service.updateHold(.failed(session, stoppedAt: 10.3), enabled: true, volume: 0.12, now: 10.3)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 12)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 9)
        #expect(plays == 0)
    }

    @Test func aHoldStartsOnceAtItsActualElapsedProgressAndEndsBeforeTheOutcome() {
        var played: [(Double, Double)] = []
        var actions: [String] = []
        let service = FeedbackSoundService(playSound: { _, _ in actions.append("outcome") },
            playEncouragement: { duration, elapsed, _ in played.append((duration, elapsed)); actions.append("progress") },
            stopEncouragement: { actions.append("stop") })
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10.4)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10.6)
        #expect(played.count == 1)
        #expect(played.first?.0 == 1.5)
        #expect(abs((played.first?.1 ?? 0) - 0.4) < 0.0001)
        service.updateHold(.completed(session), enabled: true, volume: 0.12, now: 11.5)
        service.handle(.init(sequence: 1, kind: .success, session: session, occurredAt: 11.5),
                       preferences: .init(), now: 11.5)
        #expect(actions == ["progress", "stop", "outcome"])
    }

    @Test func releaseFailureDisableAndServiceStopAllStopProgressSound() {
        var plays = 0
        var stops = 0
        let service = FeedbackSoundService(playSound: { _, _ in },
            playEncouragement: { _, _, _ in plays += 1 }, stopEncouragement: { stops += 1 })
        for terminal in [HoldPresentation?.none, .completed(session), .failed(session, stoppedAt: 10.3)] {
            service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10)
            service.updateHold(terminal, enabled: true, volume: 0.12, now: 10.3)
            service.updateHold(terminal, enabled: true, volume: 0.12, now: 10.4)
        }
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10)
        service.updateHold(.holding(session), enabled: false, volume: 0.12, now: 10.3)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10.4)
        service.stop()
        #expect(plays == 5)
        #expect(stops == 5)
    }

    @Test func deadlineStopsProgressAndPreviewCannotRestartAnActiveHold() {
        var plays = 0
        var stops = 0
        var outcomes = 0
        let service = FeedbackSoundService(playSound: { _, _ in outcomes += 1 },
            playEncouragement: { _, _, _ in plays += 1 }, stopEncouragement: { stops += 1 })
        service.previewEncouragement(duration: 1.5, volume: 0.12)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10)
        service.previewEncouragement(duration: 1.5, volume: 0.12)
        service.preview(.init(tone: .softTap, volume: 0.5))
        #expect(plays == 2)
        #expect(outcomes == 0)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 11.5)
        #expect(stops == 2)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 12)
        #expect(plays == 2)
    }

    @Test func skippedFailureSnapshotCannotSoundOverTheNextHold() {
        var actions: [String] = []
        let service = FeedbackSoundService(playSound: { _, _ in actions.append("outcome") },
            playEncouragement: { _, _, _ in actions.append("progress") },
            stopEncouragement: { actions.append("stop") })
        let retry = HoldSession(target: session.target, keyCode: session.keyCode, startedAt: 10.4, duration: 1.5)
        // The main actor receives a new hold carrying the previous hold's retained feedback.
        service.updateHold(.holding(retry), enabled: true, volume: 0.12, now: 10.5)
        service.handle(.init(sequence: 1, kind: .failure, session: session, occurredAt: 10.3),
                       preferences: .init(), now: 10.5)
        #expect(actions == ["progress"])
        service.handle(.init(sequence: 2, kind: .success, session: retry, occurredAt: 11.9),
                       preferences: .init(), now: 11.9)
        #expect(actions == ["progress", "stop", "outcome"])
    }

    @Test func matchingFailureStopsProgressAndCannotRestartFromARetainedPresentation() {
        var actions: [String] = []
        let service = FeedbackSoundService(playSound: { _, _ in actions.append("outcome") },
            playEncouragement: { _, _, _ in actions.append("progress") },
            stopEncouragement: { actions.append("stop") })
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10)
        service.handle(.init(sequence: 1, kind: .failure, session: session, occurredAt: 10.3),
                       preferences: .init(), now: 10.3)
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10.4)
        #expect(actions == ["progress", "stop", "outcome"])
    }

    @Test func mutedFailureStillEndsTheMatchingHold() {
        var stops = 0
        let service = FeedbackSoundService(playSound: { _, _ in Issue.record("Muted failure must stay silent") },
            stopEncouragement: { stops += 1 })
        var preferences = FeedbackPreferences()
        preferences.failure.enabled = false
        service.updateHold(.holding(session), enabled: true, volume: 0.12, now: 10)
        service.handle(.init(sequence: 1, kind: .failure, session: session, occurredAt: 10.3),
                       preferences: preferences, now: 10.3)
        #expect(stops == 1)
    }

    @Test(arguments: [0.5, 1.5, 3.0])
    func nativeWaveDecodesAndRisesContinuouslyWhileStayingQuiet(duration: Double) throws {
        let sound = try #require(NSSound(data: EncouragementCue.waveData(duration: duration)))
        #expect(abs(sound.duration - duration) < 1 / Double(EncouragementCue.sampleRate))
        #expect(!sound.loops)
        #expect(!sound.isPlaying)
        let samples = EncouragementCue.samples(duration: duration).map { Double($0) / Double(Int16.max) }
        #expect(samples.first == 0)
        #expect(abs(samples.last ?? 1) < 0.001)
        #expect((samples.map(abs).max() ?? 1) <= 0.361)
        #expect(FeedbackPreferences.defaultEncouragementVolume <= 0.12)
        let first = segment(samples, from: duration * 0.12, length: duration * 0.18)
        let last = segment(samples, from: duration * 0.7, length: duration * 0.18)
        #expect(energy(last) > energy(first) * 2)
        let jumps = zip(samples, samples.dropFirst()).map { abs($0.0 - $0.1) }
        #expect((jumps.max() ?? 1) < 0.08)
        for time in stride(from: 0.06, to: duration - 0.08, by: 0.025) {
            #expect(energy(segment(samples, from: time, length: 0.025)) > 0.0001)
        }
    }

    @Test func chosenVolumeReachesLivePlaybackAndCanChangeWithoutRestartingTheHold() {
        var played: [(Double, Double, Double)] = []
        var volumes: [Double] = []
        var stops = 0
        let service = FeedbackSoundService(playSound: { _, _ in },
            playEncouragement: { played.append(($0, $1, $2)) },
            setEncouragementVolume: { volumes.append($0) }, stopEncouragement: { stops += 1 })
        service.updateHold(.holding(session), enabled: true, volume: 0.27, now: 10)
        service.updateHold(.holding(session), enabled: true, volume: 0.52, now: 10.4)
        #expect(played.count == 1)
        #expect(played.first?.2 == 0.27)
        #expect(volumes == [0.27, 0.52])
        service.updateHold(.holding(session), enabled: true, volume: 0, now: 10.5)
        #expect(stops == 1)
        service.updateHold(.holding(session), enabled: true, volume: 0.15, now: 10.8)
        #expect(played.count == 2)
        #expect(played.last?.2 == 0.15)
        #expect(abs((played.last?.1 ?? 0) - 0.8) < 0.0001)
    }

    @Test func previewUsesTheSelectedVolumeAndZeroVolumeStaysSilent() {
        var played: [Double] = []
        var adjusted: [Double] = []
        let service = FeedbackSoundService(playSound: { _, _ in },
            playEncouragement: { _, _, volume in played.append(volume) },
            setEncouragementVolume: { adjusted.append($0) })
        service.previewEncouragement(duration: 1.5, volume: 0)
        service.updateHold(.holding(session), enabled: true, volume: 0, now: 10)
        #expect(played.isEmpty)
        service.previewEncouragement(duration: 1.5, volume: 0.33)
        service.updateHold(nil, enabled: false, volume: 0.44, now: 10.2)
        #expect(played == [0.33])
        #expect(adjusted.last == 0.44)
    }

    @Test func aRisingPartialContinuesAcrossTheFirstSpectralCycle() {
        let samples = EncouragementCue.samples(duration: 3).map { Double($0) / Double(Int16.max) }
        // Track an octave component before and after the spectrum cycles at
        // 1.5 seconds. The dominant register stays bounded as voices crossfade.
        for time in [0.2, 1.7] {
            let lower = 440 * pow(2, time / 1.5 - floor(time / 1.5))
            let window = segment(samples, from: time, length: 0.08)
            #expect(power(window, frequency: lower * pow(2, 0.04 / 1.5)) >
                    power(window, frequency: lower * 0.8) * 4)
        }
    }

    @Test func invalidDurationsCannotCreateUnboundedAudio() {
        for duration in [Double.nan, .infinity, -1, 0, 4] {
            #expect(EncouragementCue.waveData(duration: duration).isEmpty)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SLOWQUITGUARD_PLAY_ENCOURAGEMENT"] == "1"))
    func nativeAudioPlaybackStartsAndStops() async throws {
        let sound = try #require(NSSound(data: EncouragementCue.waveData(duration: 1.5)))
        sound.volume = Float(FeedbackPreferences.defaultEncouragementVolume)
        #expect(sound.play())
        defer { sound.stop() }
        try await Task.sleep(for: .milliseconds(180))
        #expect(sound.isPlaying)
        #expect(sound.stop())
        #expect(!sound.isPlaying)
        sound.currentTime = 1
        #expect(sound.play())
        try await Task.sleep(for: .milliseconds(180))
        #expect(sound.isPlaying)
        try await Task.sleep(for: .milliseconds(500))
        #expect(!sound.isPlaying)
    }

    private func segment(_ samples: [Double], from: Double, length: Double) -> [Double] {
        let start = Int((from * Double(EncouragementCue.sampleRate)).rounded())
        let end = min(samples.count, Int(((from + length) * Double(EncouragementCue.sampleRate)).rounded()))
        return Array(samples[start..<end])
    }

    private func energy(_ samples: [Double]) -> Double {
        samples.reduce(0) { $0 + $1 * $1 } / Double(samples.count)
    }

    private func power(_ samples: [Double], frequency: Double) -> Double {
        var real = 0.0
        var imaginary = 0.0
        for (index, sample) in samples.enumerated() {
            let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(samples.count - 1))
            let angle = 2 * .pi * frequency * Double(index) / Double(EncouragementCue.sampleRate)
            real += sample * window * cos(angle)
            imaginary += sample * window * sin(angle)
        }
        return real * real + imaginary * imaginary
    }
}
