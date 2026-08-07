import SwiftUI
import UnliRiceCore

/// The notification centre — small on purpose.
///
/// Its job is to make the app's unattended work *mentionable* without making it
/// a chore: you find out three notes look like duplicates because it's sitting
/// here next time you're in the app, not because you remembered to go and check
/// a queue. Every row points somewhere; none of them does anything.
struct NoticeCenterView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("What's happened")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !store.notices.isEmpty {
                    Button("Mark all read") { store.markAllNoticesRead() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.accentColor)
                    Button("Clear") { store.clearNotices() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if store.notices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing to report.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                    Text("""
                        This is where the app tells you what it did while you weren't \
                        here, and what needs your OK. An empty list is the normal state.
                        """)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.notices) { notice in
                            NoticeRow(notice: notice)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Text("Clearing these never touches a note. The event log is the record; this is just the news.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct NoticeRow: View {
    @EnvironmentObject var store: AppStore
    let notice: Notice

    var body: some View {
        Button(action: { store.open(notice) }) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(notice.isRead ? Color.clear : accent)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(notice.title)
                        .font(.system(size: 12.5, weight: notice.isRead ? .regular : .medium))
                        .foregroundStyle(notice.isRead ? Theme.textSecondary : Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Text(notice.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(notice.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                    if notice.destination != .none {
                        Text("open →")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(accent)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }

    /// A problem is the one kind of notice that gets a loud colour. Everything
    /// else here is news, and news that shouts is news you learn to ignore.
    private var accent: Color {
        switch notice.kind {
        case .problem: return Theme.crit
        case .review: return Theme.brass
        case .retrospective: return Theme.violet
        case .routine: return Theme.accentColor
        }
    }
}
