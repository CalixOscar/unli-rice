import SwiftUI
import UnliRiceCore

public struct NoteDetailView: View {
    @ObservedObject var store: CaptureStore
    let capture: SentCaptureItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = CapturePlayer()
    @State private var note: Note? = nil
    @State private var draftAppend: String = ""
    @State private var appendError: String? = nil

    public init(store: CaptureStore, capture: SentCaptureItem) {
        self.store = store
        self.capture = capture
    }

    private var isRecordingThisNote: Bool {
        store.appendTargetNoteID == capture.id && isRecording
    }

    private var isTranscribingThisNote: Bool {
        store.appendTargetNoteID == capture.id && isTranscribing
    }

    private var isRecording: Bool {
        if case .recording = store.state { return true }
        return false
    }

    private var isTranscribing: Bool {
        if case .transcribing = store.state { return true }
        return false
    }

    private var isBusyElsewhere: Bool {
        switch store.state {
        case .idle, .completed, .error:
            return false
        case .recording, .paused, .transcribing:
            return store.appendTargetNoteID != capture.id
        }
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Theme.bgMain
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        playbackSection
                        transcriptSection
                        appendSection
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if isRecordingThisNote {
                            store.stopAndProcess()
                        }
                        if player.isPlaying(noteID: capture.id) {
                            player.stop()
                        }
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                }
            }
            .onAppear {
                loadNote()
            }
            .onDisappear {
                if player.isPlaying(noteID: capture.id) {
                    player.stop()
                }
            }
            .onChange(of: store.state) { newState in
                if case .completed = newState {
                    loadNote()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadNote() {
        note = try? store.noteService.getNote(id: capture.id)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note?.title ?? capture.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                Text((note?.createdAt ?? capture.timestamp).formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)

                if let tags = note?.tags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(tags).sorted(), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accentSoft)
                                .foregroundStyle(Theme.accentColor)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    private var playbackSection: some View {
        let isPlaying = player.isPlaying(noteID: capture.id)
        let hasAudio = capture.audioURL != nil

        return VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                player.toggle(noteID: capture.id, audioURL: capture.audioURL)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : (hasAudio ? "play.circle.fill" : "waveform"))
                        .font(.system(size: 20))
                    Text(isPlaying ? "Stop audio" : (hasAudio ? "Play recording" : "Recording no longer stored"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(hasAudio ? Theme.accentColor : Theme.textLight)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .solidControl(cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .disabled(!hasAudio)

            if let message = player.errorMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.crit)
            }
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSCRIPT")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            let bodyText = note?.body ?? ""
            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("No transcript available.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textLight)
                    .italic()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: 12)
    }

    private var appendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD TO THIS NOTE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            // Voice append button
            HStack(spacing: 12) {
                Button(action: {
                    if isRecordingThisNote {
                        store.stopAndProcess()
                    } else {
                        store.startAppendRecording(targetNoteID: capture.id)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isRecordingThisNote ? "square.fill" : "mic.fill")
                            .font(.system(size: 13))
                        Text(isRecordingThisNote ? "Stop Voice Append" : "Add by Voice")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .foregroundStyle(isRecordingThisNote ? Theme.crit : Theme.onAccent)
                    .background(isRecordingThisNote ? Theme.crit.opacity(0.15) : Theme.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isBusyElsewhere)

                if isRecordingThisNote {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.crit).frame(width: 8, height: 8)
                        Text("Recording append…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.crit)
                    }
                } else if isTranscribingThisNote {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing voice append…")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            // Keyboard append
            VStack(alignment: .trailing, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draftAppend.isEmpty {
                        Text("Append more, any time — this is what makes it a memory rather than a one-shot note.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $draftAppend)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70, maxHeight: 120)
                        .padding(8)
                }
                .background(Theme.bgField)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
                .cardStyle(cornerRadius: 12)

                HStack {
                    if let appendError = appendError {
                        Text(appendError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.crit)
                    }
                    Spacer()
                    Button("Append") {
                        let text = draftAppend
                        draftAppend = ""
                        do {
                            try store.appendToCapture(noteID: capture.id, text: text)
                            loadNote()
                            appendError = nil
                        } catch {
                            appendError = error.localizedDescription
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentColor)
                    .cornerRadius(8)
                    .disabled(draftAppend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
