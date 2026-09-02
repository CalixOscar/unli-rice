import SwiftUI
import UnliRiceCore

public struct TranscriptionLanguageListView: View {
    @ObservedObject var store: CaptureStore

    public init(store: CaptureStore) {
        self.store = store
    }

    /// What "Follow system" actually resolves to. This is the KEYBOARD-derived locale,
    /// not the region setting — see `KeyboardLocales`. Showing the region here while
    /// transcribing in a keyboard language would be a label that lies.
    private var systemLanguageName: String {
        let resolved = KeyboardLocales.preferred()
        return Locale.current.localizedString(forIdentifier: resolved.identifier)
            ?? resolved.identifier
    }

    /// Nil when there were no readable keyboards and we fell back to the region setting.
    private var systemLanguageReason: String {
        KeyboardLocales.explanation() ?? "From your iPhone's Language & Region setting"
    }

    public var body: some View {
        ZStack {
            Theme.bgMain
                .ignoresSafeArea()

            List {
                Section {
                    Button(action: {
                        store.transcriptionLocaleID = ""
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Follow system")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("(\(systemLanguageName))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if store.transcriptionLocaleID.isEmpty {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.accentColor)
                            }
                        }
                    }
                } footer: {
                    Text(systemLanguageReason + ". Change it here if you speak a different "
                         + "language than you type.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textLight)
                }

                Section {
                    if store.availableLocales.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Loading available languages…")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        ForEach(store.availableLocales, id: \.identifier) { locale in
                            languageRow(locale)
                        }
                    }
                } header: {
                    Text("Available Languages")
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    Text("Transcription models run on-device. Downloading a language model "
                         + "requires an internet connection once.\n\nOne language is used per "
                         + "recording. Mixed-language speech — switching between two languages "
                         + "in one sentence — is not supported, and picking either language "
                         + "will not transcribe the other.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textLight)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.loadAvailableLocalesIfNeeded()
        }
    }

    private func languageRow(_ locale: Locale) -> some View {
        let isSelected = store.transcriptionLocaleID == locale.identifier
        let status = store.localeStatuses[locale.identifier] ?? .available
        let isDownloading = store.downloadingLocaleIDs.contains(locale.identifier) || status == .downloading
        let displayName = TranscriptionLanguages.displayName(for: locale)

        return HStack {
            Button(action: {
                store.transcriptionLocaleID = locale.identifier
                if status == .available {
                    store.downloadLocale(locale)
                }
            }) {
                HStack {
                    Text(displayName)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
            } else {
                switch status {
                case .installed:
                    Text("Installed")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.emerald)
                case .available:
                    Button(action: {
                        store.downloadLocale(locale)
                    }) {
                        Text("Download")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.accentSoft)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                case .downloading:
                    ProgressView().controlSize(.small)
                case .unsupported:
                    Text("Unsupported")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textLight)
                }
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                    .padding(.leading, 6)
            }
        }
    }
}
