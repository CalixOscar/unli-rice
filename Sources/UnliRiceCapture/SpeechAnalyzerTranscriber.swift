import Foundation
import Speech

public enum TranscriberError: Error, LocalizedError {
    case speechRecognizerUnavailable
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognizer is unavailable on this device or locale."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

public final class SpeechAnalyzerTranscriber: Transcriber, @unchecked Sendable {
    public let locale: Locale

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    public func transcribe(audioURL: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriberError.speechRecognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var hasResponded = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResponded else { return }
                if let error = error {
                    hasResponded = true
                    continuation.resume(throwing: TranscriberError.transcriptionFailed(error.localizedDescription))
                    return
                }
                if let result = result, result.isFinal {
                    hasResponded = true
                    let transcript = result.bestTranscription.formattedString
                    continuation.resume(returning: transcript)
                }
            }
        }
    }
}
