import SwiftUI

/// One-time welcome shown before the first capture: how to use the mic,
/// and what happens to the recording. Shown once via `@AppStorage`;
/// the shared-folder choice (privacy for *sync*) already lives in its own
/// alert, so this only covers on-device handling and points at Settings
/// for the sync decision rather than duplicating it.
struct WelcomeSplashView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.bgMain.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accentColor)

                Text("Welcome to Unli Rice")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 16)

                Text("Voice capture & memory")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 20) {
                    row(icon: "mic.fill", title: "Tap to record",
                        body: "Tap the mic to start, tap again to stop. Your words are transcribed into a note automatically.")
                    row(icon: "square.and.arrow.down.on.square", title: "It's saved as a note",
                        body: "Every recording becomes a searchable note in Unli Thoughts — tap to archive or delete.")
                    row(icon: "lock.shield.fill", title: "Private by default",
                        body: "Transcription happens entirely on this device — audio never leaves your phone or goes to a server. Choose an iCloud folder later in Settings if you want notes to sync to your Mac; until then, nothing leaves this phone.")
                }
                .padding(.top, 28)
                .padding(.horizontal, 28)

                Spacer(minLength: 24)

                Button(action: onDismiss) {
                    Text("Get Started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accentColor))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private func row(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
