import SwiftUI
import UnliRiceCore

/// Home status screen — answers "What is this app doing for me?".
/// Contains exactly three primary blocks plus conditional review callouts.
struct HomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Block 1 — App Purpose Statement
                purposeBlock

                // Block 2 — Is it working, and the primary action
                statusBlock

                // Conditional — Needs Attention callout
                if needsAttentionCount > 0 {
                    needsAttentionCard
                }

                // Block 3 — What happened (Recent Note Writes)
                recentWritesBlock
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
    }

    // MARK: - Block 1: Purpose Statement

    private var purposeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One memory your AI tools share.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Tell something to Claude, and ChatGPT knows it too.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Block 2: Working Status & Primary Action

    private var isConnected: Bool {
        !store.connectionActivities.isEmpty
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isConnected ? Theme.emerald : Theme.brass)
                    .frame(width: 10, height: 10)
                    .shadow(color: isConnected ? Theme.emerald : Theme.brass, radius: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.connectedToolsStatusText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if let lastWrite = store.lastWriteEvent {
                        let author = lastWrite.source.capitalized
                        let timeAgo = lastWrite.timestamp.formatted(.relative(presentation: .named))
                        Text("Last write: \(author), \(timeAgo)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("No notes written yet.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()
            }

            Divider().opacity(0.12)

            HStack {
                Button(action: {
                    store.copyContextToClipboard()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard.fill")
                        Text("Copy memory for ChatGPT")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(Theme.onSolidFill)
                    .solidControl(cornerRadius: 6)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(18)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Block 3: Recent Writes

    private var recentWritesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT HAPPENED RECENTLY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            if store.recentEvents.isEmpty {
                Text("No recent writes recorded.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgField)
                    .cornerRadius(6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(store.recentEvents.prefix(5)), id: \.id) { event in
                        HStack(spacing: 8) {
                            Text(event.source.capitalized)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.accentColor)

                            Text(eventDescription(for: event))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(event.timestamp.formatted(.relative(presentation: .named)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(10)
                        .background(Theme.bgField)
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    private func eventDescription(for event: Event) -> String {
        let title = event.title ?? "Note"
        switch event.kind {
        case .created:
            return "created \"\(title)\""
        case .appended:
            return "appended to \"\(title)\""
        case .tagged:
            return "tagged \"\(title)\" with '\(event.tag ?? "")'"
        case .untagged:
            return "removed tag '\(event.tag ?? "")' from \"\(title)\""
        case .archived:
            return "archived \"\(title)\""
        case .unarchived:
            return "unarchived \"\(title)\""
        case .flagged:
            return "flagged \"\(title)\""
        case .reviewResolved:
            return "resolved review for \"\(title)\""
        case .unrecognized:
            return "updated \"\(title)\""
        }
    }

    // MARK: - Conditional Block: Needs Attention

    private var needsAttentionCount: Int {
        store.pending.count + store.unreadNoticeCount
    }

    private var needsAttentionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.brass)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(needsAttentionCount) item\(needsAttentionCount == 1 ? "" : "s") waiting for your decision")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Tidying proposals and notices require your sign-off.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button("Review Items →") {
                store.showNeedsYou()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.brass)
            .solidControl(cornerRadius: 6)
        }
        .padding(14)
        .liquidGlass(cornerRadius: 8)
    }
}
