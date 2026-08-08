import SwiftUI
import UnliRiceCore

/// Home status screen — answers "What is this app doing for me?".
/// Leads with what the AI knows about you, legible recent activity, and silence diagnostics.
struct HomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Block 1 — App Purpose Header
                purposeHeader

                // Block 2 — What your AI knows about you (R5.1)
                whatAIKnowsCard

                // Block 3 — Working Status & Local Process Reassurance
                statusBlock

                // Conditional — Needs Attention Callout
                if needsAttentionCount > 0 {
                    needsAttentionCard
                }

                // Block 4 — What Happened Recently & Silence Diagnosis (R5.2)
                recentWritesBlock
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
    }

    // MARK: - Purpose Header

    private var purposeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One memory your AI tools share.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text("Tell something to Claude, and ChatGPT knows it too.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Block 2: What Your AI Knows About You (R5.1)

    private var whatAIKnowsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WHAT YOUR AI KNOWS ABOUT YOU")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(store.notes.count) notes stored")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.accentColor)
            }

            if let summary = store.summaryOfWhatAIKnows {
                Text(summary)
                    .font(.system(size: 13, design: .default))
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgField)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider().opacity(0.12)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude reads this automatically. ChatGPT needs a copy-paste.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

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
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No memory profile written yet.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Your connected AI will learn about you and build your shared memory automatically, or you can start one now.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    HStack {
                        Button("Start Profile") {
                            store.showProfileBuilder()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        Spacer()
                    }
                }
                .padding(14)
                .background(Theme.bgField)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(18)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Block 3: Working Status & Local Process Reassurance (R5.3 & R5.4)

    private var isConnected: Bool {
        !store.connectionActivities.isEmpty
    }

    private var statusBlock: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(isConnected ? Theme.emerald : Theme.brass)
                .frame(width: 10, height: 10)
                .shadow(color: isConnected ? Theme.emerald : Theme.brass, radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.connectedToolsStatusText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let lastWrite = store.lastWriteEvent {
                    let author = humanReadableSource(lastWrite.source)
                    let timeAgo = lastWrite.timestamp.formatted(.relative(presentation: .named))
                    Text("Last write: \(author), \(timeAgo)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("No notes written yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Text("Local process on this Mac — no remote network listener.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }

            Spacer()
        }
        .padding(14)
        .liquidGlass(cornerRadius: 8)
    }

    // MARK: - Block 4: Recent Writes & Silence Diagnosis (R5.2)

    private var knowledgeEvents: [Event] {
        store.recentEvents.filter { $0.kind == .created || $0.kind == .appended }
    }

    private var recentWritesBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT HAPPENED RECENTLY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            if knowledgeEvents.isEmpty {
                Text("No recent knowledge writes recorded.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgField)
                    .cornerRadius(6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(knowledgeEvents.prefix(5)), id: \.id) { event in
                        HStack(spacing: 8) {
                            Text(humanReadableSource(event.source))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.accentColor)

                            Text(humanReadableEventDescription(for: event))
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

            // Silence Diagnosis Card
            silenceDiagnosisCard
        }
    }

    private var silenceDiagnosisCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.routinesEnabled {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Background collecting is off, so nothing is being added on its own.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    Button("Turn On") {
                        store.routinesEnabled = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(12)
                .background(Theme.bgField)
                .cornerRadius(6)
            } else if store.claudeProjectsURL == nil {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Claude Code sessions aren't being indexed — they're on this Mac but Unli Rice can't see them yet.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    Button("Choose Folder") {
                        store.chooseClaudeProjectsFolder()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.accentColor)
                    .solidControl(cornerRadius: 6)
                }
                .padding(12)
                .background(Theme.bgField)
                .cornerRadius(6)
            } else if let diagnostic = store.unwrittenClientsDiagnostic {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    Button("Review Rules") {
                        store.showHouseRules()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.brass)
                    .solidControl(cornerRadius: 6)
                }
                .padding(12)
                .background(Theme.bgField)
                .cornerRadius(6)
            } else {
                HStack {
                    Text("Nothing new since then.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private func humanReadableSource(_ rawSource: String) -> String {
        switch rawSource.lowercased() {
        case "ingest", "janitor":
            return "Unli Rice"
        case "human":
            return "You"
        case "claude-code", "claude":
            return "Claude"
        default:
            return rawSource.capitalized
        }
    }

    private func humanReadableEventDescription(for event: Event) -> String {
        var title = event.title ?? "Note"
        if title.hasPrefix("Doc: raw/") {
            let filename = title.components(separatedBy: "-").dropFirst().joined(separator: "-")
            title = filename.isEmpty ? "document" : filename
            return "Indexed \(title) from your Projects folder"
        }
        switch event.kind {
        case .created:
            return "created \"\(title)\""
        case .appended:
            return "appended to \"\(title)\""
        default:
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
