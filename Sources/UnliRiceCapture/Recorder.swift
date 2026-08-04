import AVFoundation
import Foundation

public enum RecorderError: Error, LocalizedError {
    case recordingFailed(String)

    public var errorDescription: String? {
        switch self {
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

    public func startRecording(outputDirectory: URL) throws -> URL {
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
