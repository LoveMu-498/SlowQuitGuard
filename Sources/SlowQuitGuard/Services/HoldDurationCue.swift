import Foundation
import QuitGuardCore

enum HoldDurationCue {
    private static let shorter = makeWave(duration: 0.12, from: 940, to: 620,
        attack: 0.006, harmonic: 0.23)
    private static let longer = makeWave(duration: 0.20, from: 440, to: 690,
        attack: 0.026, harmonic: 0.08)

    static func waveData(for relation: HoldDurationRelation) -> Data? {
        switch relation {
        case .standard: nil
        case .shorter: shorter
        case .longer: longer
        }
    }

    private static func makeWave(duration: Double, from startFrequency: Double, to endFrequency: Double,
                                 attack: Double, harmonic: Double) -> Data {
        let rate = Double(MonoWave.sampleRate)
        let samples = (0..<Int((duration * rate).rounded())).map { index -> Int16 in
            let time = Double(index) / rate
            let phase = 2 * .pi * (startFrequency * time + (endFrequency - startFrequency) * time * time / (2 * duration))
            let onset = sin(min(1, time / attack) * .pi / 2)
            let release = sin(min(1, (duration - time) / 0.045) * .pi / 2)
            let wave = sin(phase) + harmonic * sin(2 * phase)
            let value = 0.5 * wave * onset * onset * release * release
            return Int16((value * Double(Int16.max)).rounded())
        }
        return MonoWave.encode(samples)
    }
}
