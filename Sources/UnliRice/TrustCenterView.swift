import SwiftUI
import UnliRiceCore

struct TrustCenterView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    doctorCard
                    connectionCard
                    recoveryCard
                    trashCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.refreshTrustCenter() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trust Center")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if store.trustBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Run checks") { store.refreshTrustCenter() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.accentColor)
                    .solidControl(cornerRadius: 6)
            }
            Text("Proof that assistants can reach this vault, plus verified ways back when something goes wrong.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
            if let message = store.trustMessage {
                Text(message)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.brass)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var doctorCard: some View {
        TrustCard(
            title: "Connection Doctor",
            subtitle: "Read-only checks against the active vault and local MCP activity.",
            icon: "stethoscope"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.trustChecks) { check in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: symbol(for: check.state))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color(for: check.state))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(check.detail)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    if check.id != store.trustChecks.last?.id {
                        Divider().overlay(Theme.borderLight.opacity(0.6))
                    }
                }
            }
        }
    }

    private var connectionCard: some View {
        TrustCard(
            title: "Assistant activity",
            subtitle: "Client name, time, and tool only. Unli Rice never copies tool arguments or note contents into this diagnostic log.",
            icon: "cable.connector"
        ) {
            if store.connectionActivities.isEmpty {
                Text("No client has checked in since this feature was installed. Restart a connected assistant, then ask it to search these notes.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.connectionActivities) { activity in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(activityColor(activity))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clientLabel(activity))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(activityLine(activity))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var recoveryCard: some View {
        TrustCard(
            title: "Recovery points",
            subtitle: "Byte-for-byte event history, raw sources, and vault sidecars with a SHA-256 manifest.",
            icon: "externaldrive.badge.timemachine"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    actionButton("Create recovery point", color: Theme.accentColor) {
                        Task { await store.createRecoveryPoint() }
                    }
                    actionButton("Reveal in Finder", color: Theme.textSecondary) {
                        store.revealRecoveryPoints()
                    }
                    Spacer()
                }
                .disabled(store.trustBusy)

                if store.vaultSnapshots.isEmpty {
                    Text("No recovery points yet.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(store.vaultSnapshots) { snapshot in
                        Divider().overlay(Theme.borderLight.opacity(0.6))
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(snapshot.eventCount) events · \(snapshot.noteCount) notes · \(byteString(snapshot.totalByteCount))")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            actionButton("Verify", color: Theme.accentColor) {
                                Task { await store.verifyRecoveryPoint(snapshot) }
                            }
                            actionButton("Restore missing…", color: Theme.brass) {
                                Task { await store.restoreRecoveryPoint(snapshot) }
                            }
                        }
                        .disabled(store.trustBusy)
                    }
                }
            }
        }
    }

    private var trashCard: some View {
        TrustCard(
            title: "Recoverable trash",
            subtitle: "Notes removed from the live event log but retained with their complete history.",
            icon: "trash.slash"
        ) {
            if store.trashedNotes.isEmpty {
                Text("Trash is empty.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.trashedNotes) { record in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Trashed \(record.trashedAt.formatted(.relative(presentation: .named))) · \(record.events.count) events")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            actionButton("Restore…", color: Theme.accentColor) {
                                store.restoreFromTrash(record)
                            }
                        }
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .solidControl(cornerRadius: 5)
    }

    private func activityColor(_ activity: MCPConnectionActivity) -> Color {
        if activity.lastToolCallAt != nil {
            return activity.lastToolSucceeded == false ? Theme.brass : Theme.emerald
        }
        // Vault Mode delivery is real evidence, just not evidence of a read —
        // amber here would flag the primary path as broken while it works.
        return activity.lastContextDeliveredAt != nil ? Theme.emerald : Theme.brass
    }

    private func clientLabel(_ activity: MCPConnectionActivity) -> String {
        activity.clientVersion.map { "\(activity.clientName) \($0)" } ?? activity.clientName
    }

    private func activityLine(_ activity: MCPConnectionActivity) -> String {
        if let tool = activity.lastToolName, let date = activity.lastToolCallAt {
            let outcome = activity.lastToolSucceeded == false ? "failed" : "succeeded"
            return "\(tool) · \(outcome) · \(date.formatted(.relative(presentation: .named)))"
        }
        if let deliveredAt = activity.lastContextDeliveredAt {
            return "vault context delivered \(deliveredAt.formatted(.relative(presentation: .named)))"
        }
        return "connected \(activity.lastSeenAt.formatted(.relative(presentation: .named))), never read a note"
    }

    private func byteString(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func symbol(for state: TrustCheck.State) -> String {
        switch state {
        case .healthy: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for state: TrustCheck.State) -> Color {
        switch state {
        case .healthy: return Theme.emerald
        case .attention: return Theme.brass
        case .failed: return Theme.crit
        }
    }
}

private struct TrustCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 8)
    }
}
