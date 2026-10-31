import Foundation

public enum FlipSwoosh {
    public static let sampleRate = 44_100
    public static let duration = 0.22
    public static let peak = 0.25
    public static func samples() -> [Int16] {
        let n = Int(Double(sampleRate) * duration)            // 9702
        var seed: UInt32 = 0x2545F491
        var y1 = 0.0, y2 = 0.0
        var raw = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let x = Double(seed) / Double(UInt32.max) * 2 - 1
            let cutoff = 400 + 3200 * sin(.pi * t)
            let a = exp(-2 * .pi * cutoff / Double(sampleRate))
            y1 = (1 - a) * x + a * y1
            y2 = (1 - a) * y1 + a * y2
            raw[i] = y2 * pow(sin(.pi * t), 2)
        }
        let maxAbs = raw.map(abs).max() ?? 0
        let scale = maxAbs > 0 ? peak / maxAbs : 0
        return raw.map { Int16(($0 * scale * 32767).rounded()) }
    }

    public static func wav() -> Data {
        let values = samples()
        var data = Data()
        func write<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        write(UInt32(36 + values.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        write(UInt32(16)); write(UInt16(1)); write(UInt16(1))
        write(UInt32(sampleRate)); write(UInt32(sampleRate * 2))
        write(UInt16(2)); write(UInt16(16))
        data.append(contentsOf: "data".utf8)
        write(UInt32(values.count * 2))
        for value in values { write(value) }
        return data
    }
}
