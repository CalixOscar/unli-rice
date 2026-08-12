import AVFoundation
import Foundation

/// Plays back a capture's original audio.
///
/// Exists because transcription is the lossy step: `SpeechAnalyzer` turns "Unli
/// Rice" into "only rice" and there is no way to tell a wrong transcript from a
/// strange thought without hearing the recording. The audio is already kept —
/// `Recorder` writes `.m4a` to disk before transcription ever runs — so this is
/// a way to reach a file that was always there.
@MainActor
public final class CapturePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    /// The note currently playing, if any. One at a time: starting a second
    /// playback stops the first rather than layering them.
    @Published public private(set) var playingNoteID: UUID?
    @Published public private(set) var errorMessage: String?

    private var player: AVAudioPlayer?

    public override init() {
        super.init()
    }

    public func isPlaying(noteID: UUID) -> Bool {
        playingNoteID == noteID
    }

    public func toggle(noteID: UUID, audioURL: URL?) {
        if playingNoteID == noteID {
            stop()
            return
        }
        guard let audioURL else {
            errorMessage = "That recording is no longer on this phone."
            return
        }
        play(noteID: noteID, audioURL: audioURL)
    }

    public func play(noteID: UUID, audioURL: URL) {
        stop()
        errorMessage = nil

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            errorMessage = "That recording is no longer on this phone."
            return
        }

        do {
            // The recorder leaves the session in `.playAndRecord` with
            // `.defaultToSpeaker`; without reasserting it, playback after a
            // relaunch can come out of the earpiece at barely audible volume.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: audioURL)
            newPlayer.delegate = self
            guard newPlayer.play() else {
                errorMessage = "Could not start playback."
                return
            }
            player = newPlayer
            playingNoteID = noteID
        } catch {
            errorMessage = "Could not play that recording: \(error.localizedDescription)"
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        playingNoteID = nil
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playingNoteID = nil
        }
    }
}
