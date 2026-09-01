import AVFoundation
import Foundation
import Speech

public enum TranscriberError: Error, LocalizedError {
    case speechRecognizerUnavailable
    case localeUnsupported(Locale)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech transcription isn't available on this device."
        case .localeUnsupported(let locale):
            let name = locale.identifier
            return "Speech transcription isn't available for \(name) yet. "
                + "Your recording has been saved."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

/// Transcribes a finished recording with `SpeechAnalyzer` / `SpeechTranscriber`.
///
/// This is the API the app was specified around, rather than `SFSpeechRecognizer`:
/// the legacy recognizer is built for short, live utterances and ends a session
/// on a pause, which is the exact behaviour that motivated a dedicated capture
/// app. `SpeechAnalyzer` is designed for long-form audio and has no such cutoff.
///
/// It is also on-device by construction — the locale's model is downloaded and
/// run locally, so there is no cloud fallback to guard against and no equivalent
/// of `requiresOnDeviceRecognition` to set. Audio never leaves the phone.
///
/// Transcription runs against the `.m4a` the recorder has already written, so a
/// failure here costs the transcript and never the capture.
public final class SpeechAnalyzerTranscriber: Transcriber, @unchecked Sendable {
    public init() {}

    public func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriberError.speechRecognizerUnavailable
        }

        // The user's locale may not be one the transcriber names exactly, but an
        // equivalent often exists ("en_PH" -> "en_US").
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriberError.localeUnsupported(locale)
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        try await installAssetsIfNeeded(for: transcriber, locale: supportedLocale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: audioURL)
        } catch {
            throw TranscriberError.transcriptionFailed("Could not open the recording: \(error.localizedDescription)")
        }

        // `results` has to be draining while the analyzer runs — it is a live
        // sequence, not a value returned at the end — so start collecting first
        // and await the collector after the analysis is finalized.
        let collector = Task { () throws -> String in
            var transcript = AttributedString()
            for try await result in transcriber.results {
                transcript.append(result.text)
            }
            return String(transcript.characters)
        }

        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw TranscriberError.transcriptionFailed(error.localizedDescription)
        }

        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Locale models are downloaded on demand and shared across apps, so this is
    /// usually a no-op after the first run — but the first run needs a network,
    /// and that is a normal outcome to report rather than a crash.
    private func installAssetsIfNeeded(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
        case .unsupported:
            throw TranscriberError.localeUnsupported(locale)
        case .supported, .downloading:
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                return
            }
            do {
                try await request.downloadAndInstall()
            } catch {
                throw TranscriberError.transcriptionFailed(
                    "Could not download the speech model: \(error.localizedDescription)"
                )
            }
        @unknown default:
            return
        }
    }
}
