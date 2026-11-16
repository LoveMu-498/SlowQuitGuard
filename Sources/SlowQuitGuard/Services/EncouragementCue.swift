import Foundation
import QuitGuardCore

enum EncouragementCue {
    static let sampleRate = MonoWave.sampleRate

    static func waveData(duration: Double) -> Data {
        MonoWave.encode(samples(duration: duration))
    }

    static func samples(duration: Double) -> [Int16] {
        guard HoldDuration.range.contains(duration) else { return [] }
        let count = Int((duration * Double(sampleRate)).rounded())
        var phases = [Double](repeating: 0, count: 4)
        return (0..<count).map { index in
            let time = Double(index) / Double(sampleRate)
            var mixed = 0.0
            // Octave-spaced voices rise together; the fixed spectral envelope
            // hides each voice's return from 1760 Hz to 110 Hz at zero gain.
            for voice in phases.indices {
                let octave = (time / 1.5 + Double(voice)).truncatingRemainder(dividingBy: 4)
                let frequency = 110 * pow(2, octave)
                let weight = pow(sin(.pi * octave / 4), 2)
                mixed += weight * sin(phases[voice])
                phases[voice] = (phases[voice] + 2 * .pi * frequency / Double(sampleRate))
                    .truncatingRemainder(dividingBy: 2 * .pi)
            }
            let attack = sin(min(1, time / 0.035) * .pi / 2)
            let release = sin(min(1, (duration - time) / 0.06) * .pi / 2)
            let gain = 0.12 + 0.24 * time / duration
            let value = mixed / 2 * gain * attack * attack * release * release
            return Int16((value * Double(Int16.max)).rounded())
        }
    }

}

enum MonoWave {
    static let sampleRate = 22_050

    static func encode(_ samples: [Int16]) -> Data {
        guard !samples.isEmpty else { return Data() }
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        data.reserveCapacity(44 + Int(byteCount))
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36) + byteCount, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(byteCount, to: &data)
        let littleEndianSamples = samples.map(\.littleEndian)
        littleEndianSamples.withUnsafeBufferPointer { data.append(contentsOf: UnsafeRawBufferPointer($0)) }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
