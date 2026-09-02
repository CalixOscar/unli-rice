import XCTest
@testable import UnliRiceCore

/// `KeyboardLocales` itself needs UIKit and so cannot be tested here — this covers the
/// Core seam it feeds, which is where the bug actually was: "Follow system" hard-coded
/// `Locale.current` with no way for a caller to say what "system" means.
final class TranscriptionLocaleTests: XCTestCase {

    func testExplicitIdentifierWinsOverEverything() {
        let l = TranscriptionLocale.effectiveLocale(
            for: "fil-PH", systemDefault: Locale(identifier: "en-US"))
        XCTAssertEqual(l.identifier, "fil-PH")
    }

    /// The whole point of the change: an empty identifier resolves to the INJECTED
    /// default, so iOS can hand in a keyboard-derived locale instead of the region.
    func testEmptyIdentifierUsesTheInjectedDefault() {
        let l = TranscriptionLocale.effectiveLocale(
            for: "", systemDefault: Locale(identifier: "fil-PH"))
        XCTAssertEqual(l.identifier, "fil-PH",
                       "Follow system must honour the caller's default, not Locale.current")
    }

    /// macOS, the tests, and any caller that has nothing better keep the old behaviour.
    func testEmptyIdentifierFallsBackToCurrentWhenNoDefaultGiven() {
        XCTAssertEqual(TranscriptionLocale.effectiveLocale(for: "").identifier,
                       Locale.current.identifier)
    }

    /// Guards the regression directly: before 2026-09-02 this returned the region locale
    /// no matter what, so a Filipino keyboard on an en-PH device was transcribed as en-PH.
    func testKeyboardDefaultIsNotOverriddenByTheRegionLocale() {
        let keyboard = Locale(identifier: "fil-PH")
        let resolved = TranscriptionLocale.effectiveLocale(for: "", systemDefault: keyboard)
        XCTAssertEqual(resolved.identifier, keyboard.identifier)
        if Locale.current.identifier != keyboard.identifier {
            XCTAssertNotEqual(resolved.identifier, Locale.current.identifier)
        }
    }
}
