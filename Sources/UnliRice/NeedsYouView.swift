import UnliRiceCore
import SwiftUI

/// Merged "Needs You" screen — answers "What's waiting on me?".
/// Combines the review queue (tidying proposals) with actionable notices.
struct NeedsYouView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs You")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Proposals and notices that require your decision.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                if !store.pending.isEmpty {
                    AIReviewMenu()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .solidControl(cornerRadius: 6)
                }

                CleanupMenu(prompts: CleanupPrompts.review)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .solidControl(cornerRadius: 6)
            }

            // Quick triggers: Preview & Run Tidying
            HStack(spacing: 10) {
                Button("Preview Tidying") { Task { await store.previewJanitor() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.accentColor)
                    .solidControl(cornerRadius: 4)

                Button("Run Tidying Now") { Task { await store.runJanitorNow() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.brass)
                    .solidControl(cornerRadius: 4)

                if store.janitorBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }

                if let summary = store.janitorSummary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .disabled(store.janitorBusy)

            // Content area
            if store.pending.isEmpty && store.unreadNotices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.emerald)
                    Text("All Clear — Nothing is waiting on you.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("The tidying pipeline checks for duplicates and contradictions on schedule.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Actionable Notices if any
                        if !store.unreadNotices.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NOTICES & ALERTS")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)

                                ForEach(store.unreadNotices) { notice in
                                    noticeRow(notice)
                                }
                            }
                        }

                        // Pending Review Clusters
                        if !store.pendingClusters.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("REVIEW PROPOSALS (\(store.pending.count))")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)

                                ForEach(store.pendingClusters) { cluster in
                                    ReviewClusterCard(cluster: cluster)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func noticeRow(_ notice: Notice) -> some View {
        let isProblem = notice.kind == .problem
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isProblem ? "exclamationmark.triangle.fill" : "bell.fill")
                .font(.system(size: 12))
                .foregroundStyle(isProblem ? Theme.crit : Theme.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(notice.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Dismiss") {
                store.markNoticeRead(notice)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(10)
        .liquidGlass(cornerRadius: 6)
    }
}
