import Foundation
import Testing
@testable import QuitGuardCore

private let feedbackTarget = QuitTarget(identity: .init(processID: 99, bundleID: "test.editor"), name: "编辑器")

@Test func defaultFeedbackIsQuietAndEachOutcomeIsIndependent() {
    let preferences = FeedbackPreferences()
    #expect(preferences.success.volume == 0.12)
    #expect(preferences.cancellation.volume == 0.08)
    #expect(preferences.failure.volume == 0.30)
    #expect(preferences.success.tone != preferences.cancellation.tone)
}

@Test func soundVolumeCannotEscapeThePlaybackRange() throws {
    var sound = FeedbackSoundPreference(tone: .softTap, volume: -1)
    #expect(sound.volume == 0)
    sound.volume = .nan
    #expect(sound.volume == 0)
    sound.volume = 7
    #expect(sound.volume == 1)
    let data = Data(#"{"enabled":true,"tone":"softTap","volume":4}"#.utf8)
    #expect(try JSONDecoder().decode(FeedbackSoundPreference.self, from: data).volume == 1)
}

@Test func allSoundSelectionsSurviveEncodingWithoutChangingOtherOutcomes() throws {
    var preferences = FeedbackPreferences()
    preferences[.cancellation] = .init(enabled: false, tone: .lowDouble, volume: 0.24)
    let decoded = try JSONDecoder().decode(FeedbackPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(decoded == preferences)
    #expect(decoded.success == FeedbackPreferences().success)
    #expect(decoded.failure == FeedbackPreferences().failure)
}

@Test(arguments: HoldFeedbackKind.allCases)
func aHoldCanProduceOnlyOneOutcome(_ kind: HoldFeedbackKind) {
    var recorder = HoldFeedbackRecorder()
    let session = HoldSession(target: feedbackTarget, keyCode: 12, startedAt: 10, duration: 1)
    #expect(recorder.record(kind, for: session, at: 11)?.kind == kind)
    #expect(recorder.record(.cancellation, for: session, at: 11.1) == nil)
    #expect(recorder.latest?.sequence == 1)
}

@Test func idleRecoveryHasNoFeedbackAndANewPressHasANewOutcome() {
    var recorder = HoldFeedbackRecorder()
    #expect(recorder.record(.failure, for: nil, at: 5) == nil)
    let first = HoldSession(target: feedbackTarget, keyCode: 12, startedAt: 10, duration: 1)
    let second = HoldSession(target: feedbackTarget, keyCode: 12, startedAt: 12, duration: 1)
    recorder.record(.success, for: first, at: 11)
    let next = recorder.record(.cancellation, for: second, at: 12.1)
    #expect(next?.sequence == 2)
    #expect(next?.kind == .cancellation)
}
