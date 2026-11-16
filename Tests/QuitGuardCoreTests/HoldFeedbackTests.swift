import Foundation
import Testing
@testable import QuitGuardCore

private let feedbackTarget = QuitTarget(identity: .init(processID: 99, bundleID: "test.editor"), name: "编辑器")

@Test func defaultFeedbackIsQuietAndEachOutcomeIsIndependent() {
    let preferences = FeedbackPreferences()
    #expect(!preferences.encouragementEnabled)
    #expect(preferences.encouragementVolume == 0.12)
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
    preferences.encouragementEnabled = true
    preferences.encouragementVolume = 0.35
    preferences[.cancellation] = .init(enabled: false, tone: .lowDouble, volume: 0.24)
    let decoded = try JSONDecoder().decode(FeedbackPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(decoded == preferences)
    #expect(decoded.success == FeedbackPreferences().success)
    #expect(decoded.failure == FeedbackPreferences().failure)
}

@Test func savedSettingsFromBeforeEncouragementKeepTheirSoundsAndLeaveTheModeOff() throws {
    let data = Data(#"{"success":{"enabled":false,"tone":"lowDouble","volume":0.27},"cancellation":{"enabled":true,"tone":"softTap","volume":0.08},"failure":{"enabled":true,"tone":"lowDouble","volume":0.3}}"#.utf8)
    let preferences = try JSONDecoder().decode(FeedbackPreferences.self, from: data)
    #expect(!preferences.encouragementEnabled)
    #expect(preferences.encouragementVolume == 0.12)
    #expect(preferences.success == .init(enabled: false, tone: .lowDouble, volume: 0.27))
    #expect(preferences.cancellation == FeedbackPreferences().cancellation)
    #expect(preferences.failure == FeedbackPreferences().failure)
}

@Test func olderEncouragementSettingsKeepTheModeAndUseTheDefaultVolume() throws {
    let data = Data(#"{"encouragementEnabled":true,"success":{"enabled":false,"tone":"lowDouble","volume":0.27},"cancellation":{"enabled":true,"tone":"softTap","volume":0.08},"failure":{"enabled":true,"tone":"lowDouble","volume":0.3}}"#.utf8)
    let preferences = try JSONDecoder().decode(FeedbackPreferences.self, from: data)
    #expect(preferences.encouragementEnabled)
    #expect(preferences.encouragementVolume == 0.12)
    #expect(preferences.success == .init(enabled: false, tone: .lowDouble, volume: 0.27))
}

@Test func encouragementVolumeIsClampedDuringEditingAndDecoding() throws {
    var preferences = FeedbackPreferences()
    for invalid in [-1.0, .nan, .infinity] {
        preferences.encouragementVolume = invalid
        #expect(preferences.encouragementVolume == 0)
    }
    preferences.encouragementVolume = 7
    #expect(preferences.encouragementVolume == 1)
    let data = try JSONEncoder().encode(preferences)
    var values = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    values["encouragementVolume"] = -4
    #expect(try JSONDecoder().decode(FeedbackPreferences.self, from: JSONSerialization.data(withJSONObject: values)).encouragementVolume == 0)
}

@Test(arguments: HoldFeedbackKind.allCases)
func restoringOneOutcomeVolumeKeepsAllOtherChoices(_ kind: HoldFeedbackKind) {
    var preferences = FeedbackPreferences()
    preferences.encouragementEnabled = true
    preferences.encouragementVolume = 0.47
    for item in HoldFeedbackKind.allCases {
        preferences[item] = .init(enabled: false, tone: .lowDouble, volume: 0.73)
    }
    var expected = preferences
    expected[kind].volume = FeedbackPreferences()[kind].volume
    preferences.resetVolume(for: kind)
    #expect(preferences == expected)
    preferences.resetVolume(for: kind)
    #expect(preferences == expected)
}

@Test func restoringEncouragementVolumeKeepsItsSwitchAndOtherSounds() {
    var preferences = FeedbackPreferences()
    preferences.encouragementEnabled = true
    preferences.encouragementVolume = 0.63
    preferences.success = .init(enabled: false, tone: .softTap, volume: 0.77)
    var expected = preferences
    expected.encouragementVolume = 0.12
    preferences.resetEncouragementVolume()
    #expect(preferences == expected)
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
