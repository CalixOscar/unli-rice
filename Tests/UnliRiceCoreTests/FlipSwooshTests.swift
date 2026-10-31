import XCTest
@testable import UnliRiceCore

final class FlipSwooshTests: XCTestCase {
    func testSampleCountAndPeak() {
        let samples = FlipSwoosh.samples()
        XCTAssertEqual(samples.count, 9702)
        XCTAssertEqual(samples.first, 0); XCTAssertEqual(samples.last, 0)
        XCTAssertEqual(samples.map { abs(Int($0)) }.max(), 8192)
    }
    func testSamplesAreDeterministic() {
        XCTAssertEqual(FlipSwoosh.samples(), FlipSwoosh.samples())
    }
    func testWavHeader() {
        let data = FlipSwoosh.wav()
        XCTAssertEqual(data.count, 44 + 19_404)
        func string(_ start: Int, _ end: Int) -> String { String(decoding: data[start..<end], as: UTF8.self) }
        func number(_ start: Int, _ count: Int) -> UInt32 {
            (0..<count).reduce(0) { $0 | UInt32(data[start + $1]) << (8 * $1) }
        }
        XCTAssertEqual(string(0, 4), "RIFF"); XCTAssertEqual(string(8, 12), "WAVE")
        XCTAssertEqual(string(12, 16), "fmt "); XCTAssertEqual(string(36, 40), "data")
        XCTAssertEqual(number(22, 2), 1); XCTAssertEqual(number(24, 4), 44_100)
        XCTAssertEqual(number(34, 2), 16); XCTAssertEqual(number(40, 4), 19_404)
    }
}
