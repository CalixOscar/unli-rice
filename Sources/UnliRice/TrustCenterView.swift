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
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if store.trustBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Run checks") { store.refreshTrustCenter() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            }
            Text("Proof that assistants can reach this vault, plus verified ways back when something goes wrong.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkDim)
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
                                .foregroundStyle(Theme.ink)
                            Text(check.detail)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.inkDim)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    if check.id != store.trustChecks.last?.id {
                        Divider().overlay(Theme.border.opacity(0.6))
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
                    .foregroundStyle(Theme.inkDim)
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
                                    .foregroundStyle(Theme.ink)
                                Text(activityLine(activity))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.inkDim)
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
                    actionButton("Create recovery point", color: Theme.accent) {
                        Task { await store.createRecoveryPoint() }
                    }
                    actionButton("Reveal in Finder", color: Theme.inkDim) {
                        store.revealRecoveryPoints()
                    }
                    Spacer()
                }
                .disabled(store.trustBusy)

                if store.vaultSnapshots.isEmpty {
                    Text("No recovery points yet.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                } else {
                    ForEach(store.vaultSnapshots) { snapshot in
                        Divider().overlay(Theme.border.opacity(0.6))
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text("\(snapshot.eventCount) events · \(snapshot.noteCount) notes · \(byteString(snapshot.totalByteCount))")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.inkDim)
                            }
                            Spacer()
                            actionButton("Verify", color: Theme.accent) {
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
                    .foregroundStyle(Theme.inkDim)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.trashedNotes) { record in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text("Trashed \(record.trashedAt.formatted(.relative(presentation: .named))) · \(record.events.count) events")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.inkDim)
                            }
                            Spacer()
                            actionButton("Restore…", color: Theme.accent) {
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
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
    }

    private func activityColor(_ activity: MCPConnectionActivity) -> Color {
        if activity.lastToolCallAt != nil {
            return activity.lastToolSucceeded == false ? Theme.brass : Theme.emerald
        }
        return Theme.brass
    }

    private func clientLabel(_ activity: MCPConnectionActivity) -> String {
        activity.clientVersion.map { "\(activity.clientName) \($0)" } ?? activity.clientName
    }

    private func activityLine(_ activity: MCPConnectionActivity) -> String {
        if let tool = activity.lastToolName, let date = activity.lastToolCallAt {
            let outcome = activity.lastToolSucceeded == false ? "failed" : "succeeded"
            return "\(tool) · \(outcome) · \(date.formatted(.relative(presentation: .named)))"
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
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.01)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
