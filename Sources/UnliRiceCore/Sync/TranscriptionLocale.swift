import Foundation

/// Resolves the effective transcription locale from a persisted identifier string.
///
/// An empty identifier is the default "Follow system" setting. What "system" means is
/// **injected**, not assumed — see `systemDefault` below.
public enum TranscriptionLocale {

    /// - Parameters:
    ///   - identifier: the persisted setting. Empty means "Follow system".
    ///   - systemDefault: what "Follow system" resolves to. Defaults to `Locale.current`,
    ///     which is Settings → General → **Language & Region**.
    ///
    /// **Why this is a parameter (2026-09-02).** `Locale.current` is the device's primary
    /// language, which is *not* the languages the user actually types or speaks in. Someone
    /// in the Philippines running an en-PH device with English and Filipino keyboards
    /// installed was silently transcribed as en-PH, because the keyboard list was never
    /// consulted. iOS passes a keyboard-derived locale here instead; macOS and the tests
    /// keep `Locale.current`. Core cannot compute the keyboard default itself — that needs
    /// UIKit, which is not available on macOS.
    public static func effectiveLocale(
        for identifier: String,
        systemDefault: Locale = .current
    ) -> Locale {
        identifier.isEmpty ? systemDefault : Locale(identifier: identifier)
    }
}
