import AudioToolbox
import Foundation
import UnliRiceCore

@MainActor enum FlipSound {
    private static var initialized = false
    private static var soundID: SystemSoundID?
    private static var lastPlay: TimeInterval?

    static func play() {
        if !initialized {
            initialized = true
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("unlirice-flip-swoosh.wav")
            do { try FlipSwoosh.wav().write(to: url) } catch { return }
            var id: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return }
            var isUI: UInt32 = 1
            guard AudioServicesSetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout.size(ofValue: id)), &id, UInt32(MemoryLayout.size(ofValue: isUI)), &isUI) == noErr else {
                AudioServicesDisposeSystemSoundID(id)
                return
            }
            soundID = id
        }
        guard let soundID else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPlay, now - lastPlay < 0.08 { return }
        lastPlay = now
        AudioServicesPlaySystemSound(soundID)
    }
}
