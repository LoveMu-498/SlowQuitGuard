import AppKit
import Foundation
import QuitGuardCore
import Testing
@testable import SlowQuitGuard

@Suite(.serialized)
@MainActor
struct SoundFeedbackTests {
    private var session: HoldSession {
        HoldSession(target: .init(identity: .init(processID: 99, bundleID: "test.editor"), name: "编辑器"),
                    keyCode: 12, startedAt: 1, duration: 1)
    }

    @Test func settingsPersistWithoutWritingDefaultsOnRead() throws {
        var saved: Data?
        let store = SoundSettingsStore(load: { nil }, save: { saved = $0 })
        #expect(saved == nil)
        store.preferences[.success] = .init(enabled: false, tone: .lowDouble, volume: 0.27)
        let data = try #require(saved)
        let restored = SoundSettingsStore(load: { data }, save: { _ in Issue.record("Reading must not rewrite settings") })
        #expect(restored.preferences.success == store.preferences.success)
        #expect(restored.preferences.cancellation == FeedbackPreferences().cancellation)
    }

    @Test func invalidSavedDataKeepsQuietDefaults() {
        let store = SoundSettingsStore(load: { Data("invalid".utf8) }, save: { _ in Issue.record("No write expected") })
        #expect(store.preferences == FeedbackPreferences())
    }

    @Test func anOutcomePlaysOnceWithItsOwnSoundAndVolume() {
        var played: [(FeedbackTone, Double)] = []
        let service = FeedbackSoundService(playSound: { played.append(($0, $1)) })
        var preferences = FeedbackPreferences()
        preferences.failure = .init(tone: .softTap, volume: 0.41)
        let event = HoldFeedback(sequence: 1, kind: .failure, session: session, occurredAt: 5)
        service.handle(event, preferences: preferences, now: 5.05)
        service.handle(event, preferences: preferences, now: 6)
        #expect(played.count == 1)
        #expect(played.first?.0 == .softTap)
        #expect(played.first?.1 == 0.41)
    }

    @Test func mutedDisabledStaleAndBackgroundEventsDoNotPlayLater() {
        var plays = 0
        let service = FeedbackSoundService(playSound: { _, _ in plays += 1 })
        var preferences = FeedbackPreferences()
        preferences.success.enabled = false
        let disabled = HoldFeedback(sequence: 1, kind: .success, session: session, occurredAt: 5)
        service.handle(disabled, preferences: preferences, now: 5)
        preferences.success.enabled = true
        service.handle(disabled, preferences: preferences, now: 5.1)
        preferences.cancellation.volume = 0
        service.handle(.init(sequence: 2, kind: .cancellation, session: session, occurredAt: 6), preferences: preferences, now: 6)
        service.handle(.init(sequence: 3, kind: .failure, session: session, occurredAt: 1), preferences: preferences, now: 7)
        service.handle(nil, preferences: preferences, now: 8)
        #expect(plays == 0)
    }

    @Test func burstEventsAreThrottledAndPreviewDoesNotConsumeLiveEvents() {
        var played: [Double] = []
        let service = FeedbackSoundService(playSound: { _, volume in played.append(volume) })
        let preferences = FeedbackPreferences()
        service.preview(.init(enabled: false, tone: .softRise, volume: 0.2))
        service.handle(.init(sequence: 1, kind: .cancellation, session: session, occurredAt: 5), preferences: preferences, now: 5)
        service.handle(.init(sequence: 2, kind: .cancellation, session: session, occurredAt: 5.01), preferences: preferences, now: 5.01)
        #expect(played == [0.2, 0.08])
    }

    @Test func aFailureCanPreemptGentleFeedbackWithoutRepeatingTheAlarm() {
        var played: [Double] = []
        let service = FeedbackSoundService(playSound: { _, volume in played.append(volume) })
        let preferences = FeedbackPreferences()
        service.handle(.init(sequence: 1, kind: .cancellation, session: session, occurredAt: 5), preferences: preferences, now: 5)
        service.handle(.init(sequence: 2, kind: .failure, session: session, occurredAt: 5.04), preferences: preferences, now: 5.04)
        service.handle(.init(sequence: 3, kind: .failure, session: session, occurredAt: 5.08), preferences: preferences, now: 5.08)
        #expect(played == [0.08, 0.30])
    }

    @Test func bundledWaveFilesDecodeNativelyWithoutPlayback() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for tone in FeedbackTone.allCases {
            let url = root.appendingPathComponent("Resources/Sounds/\(tone.resourceName).wav")
            let sound = try #require(NSSound(contentsOf: url, byReference: false))
            #expect(sound.duration > 0.05 && sound.duration < 0.35)
            sound.volume = 0.12
            #expect(abs(sound.volume - 0.12) < 0.001)
            #expect(!sound.isPlaying)
            #expect(!sound.loops)
        }
    }
}
