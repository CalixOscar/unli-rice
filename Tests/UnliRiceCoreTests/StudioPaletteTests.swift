import XCTest
@testable import UnliRiceCore

final class StudioPaletteTests: XCTestCase {
    func testAllTextPairsMeetContrast() {
        for pair in StudioPalette.pairs {
            for mode in StudioPalette.Mode.allCases {
                XCTAssertGreaterThanOrEqual(
                    StudioPalette.contrastRatio(StudioPalette.hex(pair.foreground, mode), StudioPalette.hex(pair.background, mode)),
                    pair.minimum,
                    "\(pair.foreground.rawValue) on \(pair.background.rawValue) in \(mode.rawValue)"
                )
            }
        }
    }

    func testEveryTokenHasAValidHexInBothModes() {
        let valid = try! NSRegularExpression(pattern: "^#[0-9A-F]{6}$")
        for token in StudioPalette.Token.allCases {
            for mode in StudioPalette.Mode.allCases {
                let value = StudioPalette.hex(token, mode)
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                XCTAssertNotNil(valid.firstMatch(in: value, range: range), "\(token.rawValue) in \(mode.rawValue)")
            }
        }
    }
}
