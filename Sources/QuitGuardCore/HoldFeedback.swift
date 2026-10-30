import Foundation

public enum HoldFeedbackKind: String, CaseIterable, Codable, Sendable {
    case success, cancellation, failure
}

public enum FeedbackTone: String, CaseIterable, Codable, Sendable {
    case softRise, softTap, lowDouble

    public var resourceName: String { rawValue }
}

public struct FeedbackSoundPreference: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var tone: FeedbackTone
    private var storedVolume: Double
    public var volume: Double {
        get { storedVolume }
        set { storedVolume = Self.clamped(newValue) }
    }

    public init(enabled: Bool = true, tone: FeedbackTone, volume: Double) {
        self.enabled = enabled
        self.tone = tone
        storedVolume = Self.clamped(volume)
    }

    private enum CodingKeys: String, CodingKey { case enabled, tone, volume }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enabled: try values.decode(Bool.self, forKey: .enabled),
                  tone: try values.decode(FeedbackTone.self, forKey: .tone),
                  volume: try values.decode(Double.self, forKey: .volume))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(tone, forKey: .tone)
        try values.encode(volume, forKey: .volume)
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

public struct FeedbackPreferences: Equatable, Codable, Sendable {
    public var success = FeedbackSoundPreference(tone: .softRise, volume: 0.12)
    public var cancellation = FeedbackSoundPreference(tone: .softTap, volume: 0.08)
    public var failure = FeedbackSoundPreference(tone: .lowDouble, volume: 0.30)

    public init() {}

    public subscript(_ kind: HoldFeedbackKind) -> FeedbackSoundPreference {
        get {
            switch kind {
            case .success: success
            case .cancellation: cancellation
            case .failure: failure
            }
        }
        set {
            switch kind {
            case .success: success = newValue
            case .cancellation: cancellation = newValue
            case .failure: failure = newValue
            }
        }
    }
}

public struct HoldFeedback: Equatable, Sendable {
    public let sequence: UInt64
    public let kind: HoldFeedbackKind
    public let session: HoldSession
    public let occurredAt: Double

    public init(sequence: UInt64, kind: HoldFeedbackKind, session: HoldSession, occurredAt: Double) {
        self.sequence = sequence
        self.kind = kind
        self.session = session
        self.occurredAt = occurredAt
    }
}

public struct HoldFeedbackRecorder: Sendable {
    public private(set) var latest: HoldFeedback?

    public init() {}

    @discardableResult
    public mutating func record(_ kind: HoldFeedbackKind, for session: HoldSession?, at time: Double) -> HoldFeedback? {
        guard let session, latest?.session != session else { return nil }
        let event = HoldFeedback(sequence: (latest?.sequence ?? 0) + 1, kind: kind, session: session, occurredAt: time)
        latest = event
        return event
    }
}
