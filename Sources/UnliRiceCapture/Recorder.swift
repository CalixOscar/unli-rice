import AVFoundation
import Foundation
import UIKit

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
///
/// **There is no cap on how long a recording may run**, and that is a deliberate
/// property rather than an omission — the app exists because `SFSpeechRecognizer`
/// ends a session on a pause, and a recorder that quietly stopped after a few
/// minutes would reintroduce the same betrayal one layer down. `record()` is
/// called without `forDuration:`, so nothing in this file ends a recording but
/// the user. Three things outside this file used to end one anyway, and each is
/// handled here: the screen auto-locking, iOS suspending a backgrounded app, and
/// the microphone being taken away by a call. The only real ceiling left is free
/// disk space — AAC mono at 44.1kHz costs roughly 30MB an hour.
public final class Recorder: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    /// One recorder per process.
    ///
    /// There is exactly one microphone, and a recording started by the Action
    /// Button has to be stoppable from the app and vice versa. Two `Recorder`
    /// instances — which is what the app and `RecordCaptureIntent` used to
    /// create — cannot see each other's session, so a second press would open a
    /// competing recording over the first instead of ending it.
    public static let shared = Recorder()

    private var audioRecorder: AVAudioRecorder?
    public private(set) var currentAudioURL: URL?
    private var interruptionObserver: NSObjectProtocol?

    /// Whether a recording is in flight. True while paused by an interruption
    /// too — the session still exists and is still the user's recording.
    public var isRecording: Bool {
        audioRecorder != nil
    }

    /// Called when iOS takes the microphone away mid-recording and hands it back
    /// — a phone call, Siri, another app. `true` means recording resumed into the
    /// same file and nothing was lost; `false` means it could not be resumed and
    /// the audio captured up to that point is what there is.
    ///
    /// Without this the recorder was simply stopped by the system while the UI
    /// went on claiming it was recording, which is the worst of both: a truncated
    /// capture and no way to know it happened.
    public var onInterruption: ((Bool) -> Void)?

    public override init() {
        super.init()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
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
        // No `forDuration:`. An open-ended recording is the whole point.
        guard recorder.record() else {
            throw RecorderError.recordingFailed("Failed to start recording hardware.")
        }

        self.audioRecorder = recorder
        self.currentAudioURL = fileURL

        // Auto-lock was the real limit on recording length, and an invisible one:
        // tap record, set the phone down, and iOS dims and locks after 30
        // seconds by default. The app is then a suspended background app holding
        // a microphone, which the system does not allow — so the recording ended
        // roughly whenever the user's Auto-Lock setting said it did, with no
        // error and no indication. Held only while recording, and released in
        // `stopRecording()`, so the setting is never left changed behind us.
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        beginObservingInterruptions()

        return fileURL
    }

    public func stopRecording() -> URL? {
        audioRecorder?.stop()
        audioRecorder = nil
        endObservingInterruptions()
        Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false }
        return currentAudioURL
    }

    /// A call, Siri, or another app claiming the microphone pauses an
    /// `AVAudioRecorder` rather than destroying it, so the recording can be
    /// resumed into the same file once the system offers it back. Taking that
    /// offer is what makes a long recording survive an interruption instead of
    /// silently ending at it.
    private func beginObservingInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

            switch type {
            case .began:
                self.audioRecorder?.pause()
            case .ended:
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                guard options.contains(.shouldResume) else {
                    self.onInterruption?(false)
                    return
                }
                try? AVAudioSession.sharedInstance().setActive(true)
                self.onInterruption?(self.audioRecorder?.record() == true)
            @unknown default:
                break
            }
        }
    }

    private func endObservingInterruptions() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }
}
