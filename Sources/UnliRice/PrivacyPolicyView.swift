import SwiftUI

/// The in-app copy of the privacy policy. App Store Connect still needs a
/// public URL for this same text before submission; keeping it here makes the
/// policy available even when the Mac is offline.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy")
                    .font(.system(size: 24, weight: .bold, design: .serif))

                policySection(
                    "No collection",
                    "Unli Rice has no account, analytics, advertising, tracking, purchases, or developer-operated server. Your notes and settings stay on your Mac. calmdownoscar does not receive them."
                )
                policySection(
                    "Files you choose",
                    "Unli Rice reads or writes outside its own container only after you select a folder in the macOS file picker. It stores a security-scoped bookmark so scheduled work can keep using that folder. You can remove Claude session access in Automation and switch the note store in Connect."
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
                    "Notes remain in the store you control until you archive and permanently remove them from Trash. Removing the app does not delete a store you placed in another folder. You can export your notes at any time."
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

                Text("Effective July 21, 2026")
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
