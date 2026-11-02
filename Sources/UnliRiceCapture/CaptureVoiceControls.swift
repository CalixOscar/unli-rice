import SwiftUI

struct CaptureVoiceControls: View {
    @ObservedObject var store: CaptureStore
    @ObservedObject private var lock = AppLock.shared
    private var recording: Bool { if case .recording = store.state { return true }; return false }
    private var paused: Bool { if case .paused = store.state { return true }; return false }
    private var transcribing: Bool { if case .transcribing = store.state { return true }; return false }
    var body: some View {
        if !lock.isLocked {
        ZStack {
            Theme.bgMain.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Project: \(store.currentProjectTab)").font(.headline)
                Image(systemName: recording ? "pause.fill" : (paused ? "play.fill" : "mic.fill"))
                    .font(.system(size: 26)).foregroundStyle(Theme.onAccent)
                    .frame(width: 68, height: 68).background(recording ? Theme.crit : Theme.accentColor, in: Circle())
                    .contentShape(Circle())
                    .gesture(store.recordingMode == .holdToRecord ? DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !recording && !paused { store.startRecording() } }
                        .onEnded { _ in if recording { store.pauseRecording() } } : nil)
                    .onTapGesture { if store.recordingMode == .tapToToggle && store.appendTargetNoteID == nil { store.toggleRecording() } }
                    .disabled(store.appendTargetNoteID != nil || transcribing)
                    .accessibilityLabel(transcribing ? "Transcribing voice note" : (recording ? "Pause recording" : (paused ? "Resume recording" : "Record")))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        if store.appendTargetNoteID == nil && !transcribing {
                            if recording { store.pauseRecording() }
                            else if paused { store.resumeRecording() }
                            else { store.startRecording() }
                        }
                    }
                status
                if recording || paused {
                    HStack(spacing: 32) {
                        Button { if paused { store.resumeRecording() } else { store.pauseRecording() } } label: {
                            Text(paused ? "Resume" : "Pause").frame(minWidth: 44, minHeight: 44)
                        }
                        Button { store.stopAndProcess() } label: {
                            Text("Stop & Save").frame(minWidth: 44, minHeight: 44)
                        }
                    }
                }
            }.padding()
        }
        }
    }
    @ViewBuilder private var status: some View {
        switch store.state {
        case .idle: Text(store.recordingMode == .holdToRecord ? "Press and hold mic to record" : "Tap mic to record a thought")
        case .recording: Text("Recording… \(duration)")
        case .paused: Text("Paused · \(duration)")
        case .transcribing: ProgressView("Transcribing voice note…")
        case .completed: Text("Voice note saved")
        case .error(let message): Text(message)
        }
    }
    private var duration: String { String(format: "%02d:%02d", Int(store.recordingDuration) / 60, Int(store.recordingDuration) % 60) }
}
