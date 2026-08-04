import SwiftUI

public struct CaptureView: View {
    @StateObject private var store: CaptureStore

    @MainActor
    public init(store: CaptureStore? = nil) {
        _store = StateObject(wrappedValue: store ?? CaptureStore())
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
            recordButton
            statusView
            Divider()
            capturesList
        }
        .padding(20)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Unli Rice")
                .font(.system(size: 24, weight: .bold, design: .serif))
            Text("Voice Capture Companion")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var recordButton: some View {
        Button(action: { store.toggleRecording() }) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 80, height: 80)
                Image(systemName: isRecording ? "square.fill" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var isRecording: Bool {
        if case .recording = store.state { return true }
        return false
    }

    private var statusView: some View {
        VStack(spacing: 6) {
            switch store.state {
            case .idle:
                Text("Tap mic to record a thought")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            case .recording:
                Text("Recording… Tap to finish")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing voice note…")
                        .font(.system(size: 13))
                }
            case .completed(let title):
                Text("Saved: “\(title)”")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
            case .error(let msg):
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if !store.partialTranscript.isEmpty && store.state != .idle {
                Text(store.partialTranscript)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    private var capturesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Captures (\(store.captures.count))")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            if store.captures.isEmpty {
                Text("No captures recorded yet.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.captures) { item in
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 14))
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
}
