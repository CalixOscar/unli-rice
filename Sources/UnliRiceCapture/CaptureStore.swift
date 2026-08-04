import Foundation
import SwiftUI
import UnliRiceCore

public struct SentCaptureItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let timestamp: Date
    public let audioURL: URL

    public init(id: UUID, title: String, timestamp: Date, audioURL: URL) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.audioURL = audioURL
    }
}

@MainActor
public final class CaptureStore: ObservableObject {
    public enum State: Equatable {
        case idle
        case recording(audioURL: URL)
        case transcribing(audioURL: URL)
        case completed(title: String)
        case error(String)
    }

    @Published public var state: State = .idle
    @Published public var partialTranscript: String = ""
    @Published public var captures: [SentCaptureItem] = []

    private let recorder: Recorder
    private let transcriber: Transcriber
    private let shardWriter: ShardWriter
    private let storageDir: URL

    public init(
        storageDir: URL? = nil,
        transcriber: Transcriber = SpeechAnalyzerTranscriber()
    ) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseDir = storageDir ?? docs.appendingPathComponent("UnliRiceCapture", isDirectory: true)
        self.storageDir = baseDir
        self.recorder = Recorder()
        self.transcriber = transcriber

        let deviceIdentity = DeviceIdentity.current(inDirectory: baseDir)
        let shardFile = baseDir.appendingPathComponent("shards", isDirectory: true)
            .appendingPathComponent("events-\(deviceIdentity.id).jsonl")
        self.shardWriter = ShardWriter(shardFileURL: shardFile, deviceLabel: deviceIdentity.label)
    }

    public func toggleRecording() {
        switch state {
        case .idle, .completed, .error:
            startRecording()
        case .recording:
            stopAndProcess()
        case .transcribing:
            break
        }
    }

    public func startRecording() {
        // Asking for microphone access is asynchronous, so starting is too.
        Task {
            do {
                let audioURL = try await recorder.startRecording(
                    outputDirectory: storageDir.appendingPathComponent("Audio")
                )
                state = .recording(audioURL: audioURL)
                partialTranscript = "Recording audio…"
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    public func stopAndProcess() {
        guard let audioURL = recorder.stopRecording() else {
            state = .error("No audio file recorded.")
            return
        }

        state = .transcribing(audioURL: audioURL)
        partialTranscript = "Transcribing audio..."

        Task {
            do {
                let transcript = try await transcriber.transcribe(audioURL: audioURL)
                let event = try shardWriter.writeCapture(transcript: transcript)

                let item = SentCaptureItem(
                    id: event.id,
                    // `ShardWriter` always sets a title, and already falls back
                    // to a timestamped one. Mirror that here rather than
                    // reintroducing a constant the janitor would see as a
                    // duplicate of every other capture.
                    title: event.title ?? ShardWriter.timestampedFallbackTitle(for: event.timestamp),
                    timestamp: event.timestamp,
                    audioURL: audioURL
                )
                captures.insert(item, at: 0)
                state = .completed(title: item.title)
                partialTranscript = transcript
            } catch {
                // Audio file survives on disk at audioURL even if transcription fails!
                state = .error("Transcription failed: \(error.localizedDescription) (audio saved at \(audioURL.lastPathComponent))")
            }
        }
    }
}
