import Foundation
import AppIntents
import UnliRiceCore

/// App Intent for binding voice recording to the iOS Action Button, Shortcuts, or Control Center.
///
/// Uses the existing `ShardWriter` pipeline to land captures with `source: "human"` and `device: DeviceIdentity.current().label`.
@available(iOS 16.0, *)
public struct RecordCaptureIntent: AppIntent {
    public static var title: LocalizedStringResource = "Record Voice Capture"
    public static var description = IntentDescription("Records a voice capture directly into Unli Rice.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseDir = docs.appendingPathComponent("UnliRiceCapture", isDirectory: true)
        let identity = DeviceIdentity.current(inDirectory: baseDir)

        let recorder = Recorder()
        let audioDirectory = baseDir.appendingPathComponent("Audio", isDirectory: true)
        let audioURL = try await recorder.startRecording(outputDirectory: audioDirectory)

        // Record short sample / until stopped
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds sample recording for background intent
        _ = recorder.stopRecording()

        let transcriber: Transcriber = SpeechAnalyzerTranscriber()
        let transcript = try await transcriber.transcribe(audioURL: audioURL)

        let ownShardFile = baseDir.appendingPathComponent("shards", isDirectory: true)
            .appendingPathComponent("events-phone-\(identity.id).jsonl")
        let writer = ShardWriter(shardFileURL: ownShardFile, deviceLabel: identity.label)
        let event = try writer.writeCapture(transcript: transcript)

        let fallbackTitle = ShardWriter.timestampedFallbackTitle(for: event.timestamp)
        let title = event.title ?? fallbackTitle
        return .result(dialog: "Recorded voice capture: '\(title)'")
    }
}

@available(iOS 16.0, *)
public struct CaptureShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordCaptureIntent(),
            phrases: [
                "Capture voice note in \(.applicationName)",
                "Record note in \(.applicationName)"
            ],
            shortTitle: "Record Voice Capture",
            systemImageName: "mic.fill"
        )
    }
}
