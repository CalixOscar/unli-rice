import SwiftUI
import UnliRiceCore

/// Page explaining the 7 concrete technical advantages over a self-written markdown text file.
struct WhyNotTextFileView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why not just a text file?")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Anyone technical enough to build apps will make a memory.md or CLAUDE.md file and point their tools at it. Here is why a shared text file breaks down as soon as you use more than one tool:")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                }

                // 7 Technical Comparison Cards
                VStack(alignment: .leading, spacing: 14) {
                    advantageCard(
                        number: "1",
                        title: "Every write is signed",
                        body: "Each event carries exact source and device identity. A markdown file cannot tell you whether Claude, Cursor, or Codex wrote a line, or when it was added."
                    )

                    advantageCard(
                        number: "2",
                        title: "Concurrent write safety",
                        body: "Two agents can write at the exact same moment without clobbering each other. The projection cursor is a byte offset into an append-only file, so writes arrive safely as bytes past the cursor. Concurrent writes to a shared memory.md destroy each other."
                    )

                    advantageCard(
                        number: "3",
                        title: "Nothing can be destroyed",
                        body: "There is no delete operation for an agent to call anywhere in the system. Archiving is soft and fully reversible. An AI agent that decides to 'tidy up' your text file truncates it permanently — nothing brings it back."
                    )

                    advantageCard(
                        number: "4",
                        title: "Full event history per note",
                        body: "The event log records exact atomic events rather than synthetic git diffs. You can inspect how any note evolved across multiple sessions and tools."
                    )

                    advantageCard(
                        number: "5",
                        title: "Propose-don't-apply maintenance",
                        body: "The background janitor can only tag and flag. Structural changes and deduplication proposals are queued for human sign-off — an automated background process never alters your notes unattended."
                    )

                    advantageCard(
                        number: "6",
                        title: "Idempotent transcript & folder ingestion",
                        body: "Ingest pipelines scan Claude Code sessions and nominated folders using content digests. Re-running ingest updates notes cleanly without duplicating transcripts."
                    )

                    advantageCard(
                        number: "7",
                        title: "Three access channels for the same memory",
                        body: "MCP server for interactive AI sessions, plain Markdown folder (~/Documents/Unli Rice/) for local file readers like ChatGPT, and unlirice CLI for scripts — so any tool can access the exact same memory."
                    )
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
    }

    private func advantageCard(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 24, height: 24)
                .background(Theme.accentColor)
                .clipShape(Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 8)
    }
}
