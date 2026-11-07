import SwiftUI

/// The in-app copy of the privacy policy. App Store Connect still needs a
/// public URL for this same text before submission; keeping it here makes the
/// policy available even when the Mac is offline.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy")
                    .font(.system(size: 24, weight: .bold))

                policySection(
                    "No collection",
                    "Unli Rice has no app account, analytics, advertising, tracking, purchases, or developer-operated server. Notes are stored locally by default. Optional iCloud sync uses your Apple account; calmdownoscar does not receive your notes."
                )
                policySection(
                    "Files you choose",
                    "Apart from optional iCloud sync, Unli Rice reads or writes outside its own container only after you select a folder in the macOS file picker. It stores a security-scoped bookmark so scheduled work can keep using that folder. You can remove Claude session access in Automation and switch the note store in Connect."
                )
                policySection(
                    "Optional iCloud sync",
                    "When you enable sync, existing and future note text, transcripts, tags, to-dos and project summaries are shared with devices using the same Apple account. Recordings and repository files stay local. Turning sync off stops new transfers; it does not erase copies already delivered to iCloud or other devices. Account changes pause sync."
                )
                policySection(
                    "AI tools",
                    "When you manually configure an AI tool to use the bundled MCP helper, that tool can read and write your Unli Rice notes. The tool runs under its own privacy terms. Unli Rice never edits the tool's configuration for you."
                )
                policySection(
                    "Optional local embeddings",
                    "If you configure a local embedding server, Unli Rice sends note titles only to the loopback address on this Mac. Non-local addresses are rejected."
                )
                policySection(
                    "Retention and deletion",
                    "Archiving is reversible. Once a note store has been linked to native iCloud, it uses archive only, even after sync is turned off. Stores never linked to native iCloud retain their existing Trash and backup controls. Removing the app does not delete a store you placed in another folder. You can export notes at any time."
                )
                policySection(
                    "Questions",
                    "Use the public support tracker for app questions, privacy requests, or deletion help. Do not include private note content in a public issue."
                )

                HStack(spacing: 18) {
                    Link(
                        "View Privacy Policy Online",
                        destination: URL(string: "https://github.com/CalixOscar/unli-rice/blob/main/PRIVACY.md")!
                    )
                    Link(
                        "Get Support",
                        destination: URL(string: "https://github.com/CalixOscar/unli-rice/issues")!
                    )
                }
                .font(.body.weight(.medium))

                Text("Effective November 1, 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .frame(width: 660, height: 540)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
