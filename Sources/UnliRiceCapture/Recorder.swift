import AVFoundation
import Foundation

public enum RecorderError: Error, LocalizedError {
    case microphonePermissionDenied
    case audioSessionUnavailable(String)
    case recordingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Unli Rice Capture needs microphone access to record. "
                + "You can grant it in Settings › Privacy › Microphone."
        case .audioSessionUnavailable(let reason):
            return "Could not start the audio session: \(reason)"
        case .recordingFailed(let reason):
            return "Recorder error: \(reason)"
        }
    }
}

/// Audio recorder that writes .m4a directly to disk before transcription.
public final class Recorder: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    private var audioRecorder: AVAudioRecorder?
    public private(set) var currentAudioURL: URL?

    public override init() {
        super.init()
    }

    /// Asks for microphone access, if it hasn't been granted already.
    ///
    /// A usage string in Info.plist only supplies the *wording* of the prompt —
    /// something has to actually request it, or `AVAudioRecorder.record()` just
    /// returns false with no prompt and no explanation.
    public static func ensureMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    public func startRecording(outputDirectory: URL) async throws -> URL {
        guard await Self.ensureMicrophonePermission() else {
            throw RecorderError.microphonePermissionDenied
        }

        // Recording also needs an active session in a category that permits
        // input. Without this the recorder fails to start even with permission.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw RecorderError.audioSessionUnavailable(error.localizedDescription)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let filename = "capture-\(UUID().uuidString).m4a"
        let fileURL = outputDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        guard recorder.record() else {
            throw RecorderError.recordingFailed("Failed to start recording hardware.")
        }

        self.audioRecorder = recorder
        self.currentAudioURL = fileURL
        return fileURL
    }

    public func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil
        return currentAudioURL
    }
}
