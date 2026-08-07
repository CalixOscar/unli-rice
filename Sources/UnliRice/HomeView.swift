import UnliRiceCore
import SwiftUI

/// Home status screen — answers "What is this app doing for me?".
struct HomeView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title and subtitle header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Home")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                    Text("What Unli Rice is doing for you right now.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }

                // 1. Status Banner — "Memory is working" / "Not connected"
                statusCard

                // 2. Needs You Callout — if reviews or unread notices exist
                if needsAttentionCount > 0 {
                    needsAttentionCard
                }

                // 3. Profile Status / Builder Invitation
                profileSection

                // 4. Recent Activity Digest
                recentActivitySection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var needsAttentionCount: Int {
        store.pending.count + store.unreadNoticeCount
    }

    private var isConnected: Bool {
        !store.connectionActivities.isEmpty
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(isConnected ? Theme.emerald : Theme.brass)
                .frame(width: 12, height: 12)
                .shadow(color: isConnected ? Theme.emerald : Theme.brass, radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(isConnected ? "Shared Memory is Working" : "Not Connected Yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isConnected
                     ? "\(store.notes.count) notes stored · \(store.activeProfileName) active · \(store.connectionActivities.count) client interaction\(store.connectionActivities.count == 1 ? "" : "s") recorded"
                     : "Connect your AI tools in Setup so they can read and write to your shared memory.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button(isConnected ? "Setup & Tools" : "Connect AI Tool") {
                store.showGetStarted()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
        .liquidGlass(cornerRadius: 8)
    }

    private var needsAttentionCard: some View {
        HStack(spacing: 16) {
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
        .padding(16)
        .liquidGlass(cornerRadius: 8)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WHO YOU ARE (PROFILE)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(store.activeProfileName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.brass)
            }

            if hasProfileNotes {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your personalized AI context profile is active.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Connected AI assistants read your Identity, Voice, Principles, and Guardrails automatically.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 10) {
                        Button("Launch Profile Builder") {
                            store.showProfileBuilder()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.accentColor)
                        .solidControl(cornerRadius: 6)

                        Button("Manage Profiles") {
                            store.showProfileManager()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accentColor)
                        Text("Create Your AI Context Profile")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Text("Build a personalized context document set (Identity, Voice, Principles, Guardrails) that any LLM can read to understand who you are and how you work.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Build Profile →") {
                        store.showProfileBuilder()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 4)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 8)
            }
        }
    }

    private var hasProfileNotes: Bool {
        store.notes.contains { $0.title.lowercased().hasPrefix("profile:") }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            if store.notices.isEmpty {
                Text("No recent notices.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.notices.prefix(4)) { notice in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(notice.kind == .problem ? Theme.crit : Theme.accentColor)
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(notice.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(notice.detail)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(notice.timestamp.formatted(.relative(presentation: .named)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(10)
                        .liquidGlass(cornerRadius: 6)
                    }
                }
            }
        }
    }
}
