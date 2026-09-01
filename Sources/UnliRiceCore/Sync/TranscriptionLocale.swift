import Foundation

/// Resolves the effective transcription locale from a persisted identifier string.
///
/// An empty identifier string represents the default "Follow system" setting, which
/// resolves to `Locale.current`. A non-empty string resolves to `Locale(identifier:)`.
public enum TranscriptionLocale {
    public static func effectiveLocale(for identifier: String) -> Locale {
        identifier.isEmpty ? Locale.current : Locale(identifier: identifier)
    }
}
