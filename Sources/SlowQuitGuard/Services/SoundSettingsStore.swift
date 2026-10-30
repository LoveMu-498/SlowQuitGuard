import Foundation
import Observation
import QuitGuardCore

@MainActor
@Observable
final class SoundSettingsStore {
    var preferences: FeedbackPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { save(data) }
        }
    }
    @ObservationIgnored private let save: (Data) -> Void

    init(load: () -> Data?, save: @escaping (Data) -> Void) {
        preferences = load().flatMap { try? JSONDecoder().decode(FeedbackPreferences.self, from: $0) } ?? .init()
        self.save = save
    }

    static func live() -> SoundSettingsStore {
        SoundSettingsStore(load: { UserDefaults.standard.data(forKey: "soundFeedbackV1") },
            save: { UserDefaults.standard.set($0, forKey: "soundFeedbackV1") })
    }
}
