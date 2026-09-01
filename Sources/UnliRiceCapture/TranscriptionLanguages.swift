import Foundation
import Speech

public enum LanguageStatus: String, Equatable, Sendable {
    case installed
    case available
    case downloading
    case unsupported

    public var displayLabel: String {
        switch self {
        case .installed: return "Installed"
        case .available: return "Available"
        case .downloading: return "Downloading…"
        case .unsupported: return "Unsupported"
        }
    }
}

public enum TranscriptionLanguageError: Error, LocalizedError {
    case reservationCapReached(Int)
    case unsupportedLocale(Locale)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .reservationCapReached(let max):
            return "The device limit of \(max) reserved language model\(max == 1 ? "" : "s") has been reached. Please release another language model first."
        case .unsupportedLocale(let locale):
            let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return "Speech transcription is not supported for \(name)."
        case .downloadFailed(let reason):
            return "Could not download speech model: \(reason)"
        }
    }
}

public enum TranscriptionLanguages {
    /// Returns the locales supported by SpeechTranscriber, sorted by localized display name.
    public static func supported() async -> [Locale] {
        let locales = await SpeechTranscriber.supportedLocales
        let currentLocale = Locale.current
        return locales.sorted { a, b in
            let nameA = currentLocale.localizedString(forIdentifier: a.identifier) ?? a.identifier
            let nameB = currentLocale.localizedString(forIdentifier: b.identifier) ?? b.identifier
            return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
        }
    }

    /// Determines the on-device asset status for a given locale.
    public static func status(for locale: Locale) async -> LanguageStatus {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unsupported
        }

        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return .installed
        case .supported:
            return .available
        case .downloading:
            return .downloading
        case .unsupported:
            return .unsupported
        @unknown default:
            return .available
        }
    }

    /// Downloads and installs speech assets for a given locale with progress reporting.
    public static func install(
        _ locale: Locale,
        progressHandler: (@Sendable (Progress) -> Void)? = nil
    ) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionLanguageError.unsupportedLocale(locale)
        }

        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        let currentStatus = await AssetInventory.status(forModules: [transcriber])
        if currentStatus == .installed {
            return
        }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            return
        }

        progressHandler?(request.progress)

        do {
            try await request.downloadAndInstall()
        } catch {
            throw TranscriptionLanguageError.downloadFailed(error.localizedDescription)
        }
    }

    /// Reserves the model for `locale` on the device so it is not evicted by the OS.
    ///
    /// Respects `AssetInventory.maximumReservedLocales` and surfaces a plain-language error
    /// if the per-app cap is reached.
    public static func reserve(_ locale: Locale) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionLanguageError.unsupportedLocale(locale)
        }

        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(supported) {
            return
        }

        if reserved.count >= AssetInventory.maximumReservedLocales {
            throw TranscriptionLanguageError.reservationCapReached(AssetInventory.maximumReservedLocales)
        }

        do {
            _ = try await AssetInventory.reserve(locale: supported)
        } catch {
            throw TranscriptionLanguageError.downloadFailed(error.localizedDescription)
        }
    }

    /// Releases a previously reserved locale model so it may be evicted by the system.
    public static func release(_ locale: Locale) async {
        if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            _ = await AssetInventory.release(reservedLocale: supported)
        } else {
            _ = await AssetInventory.release(reservedLocale: locale)
        }
    }

    /// Returns a localized display name for the given locale.
    public static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
