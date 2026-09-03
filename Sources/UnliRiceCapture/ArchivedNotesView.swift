import SwiftUI

public struct ArchivedNotesView: View {
    @ObservedObject var store: CaptureStore
    @StateObject private var player = CapturePlayer()

    public init(store: CaptureStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Theme.bgMain
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = player.errorMessage {
                        Text(message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.crit)
                            .padding(.horizontal, 16)
                    }

                    if store.archivedCaptures.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.textLight)
                            Text("No Archived Notes")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Notes you archive will appear here. You can restore them to your active projects at any time.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ARCHIVED NOTES (\(store.archivedCaptures.count))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 16)

                            VStack(spacing: 8) {
                                ForEach(store.archivedCaptures) { item in
                                    archivedRow(item)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Archived Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func archivedRow(_ item: SentCaptureItem) -> some View {
        let isPlaying = player.isPlaying(noteID: item.id)
        let hasAudio = item.audioURL != nil

        return HStack(spacing: 10) {
            // No control at all when there is no audio, rather than a disabled one.
            // A greyed-out play button is a claim about history — "this could play,
            // but not now" — and nothing here knows whether the audio was pruned or
            // never existed: a typed note has no index entry, and neither does a
            // pruned recording after `forget(noteID:)`. Unknown stays unknown.
            if hasAudio {
                Button(action: { player.toggle(noteID: item.id, audioURL: item.audioURL) }) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Stop playback" : "Play recording")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button(action: {
                if isPlaying { player.stop() }
                store.unarchiveCapture(id: item.id)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Restore")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.accentColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Theme.accentSoft)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: {
                if isPlaying { player.stop() }
                store.deleteCapture(id: item.id)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.crit)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .cardStyle(cornerRadius: 12)
    }
}
