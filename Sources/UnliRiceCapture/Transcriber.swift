import Foundation

/// Seam for audio transcription implementations.
public protocol Transcriber: Sendable {
    func transcribe(audioURL: URL, locale: Locale) async throws -> String
}
