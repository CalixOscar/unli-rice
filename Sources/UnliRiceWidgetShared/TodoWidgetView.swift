import AppIntents
import SwiftUI
import UnliRiceCore
import WidgetKit

// Shared by the Mac widget (UnliRiceWidget) and the iPhone widget (UnliRiceCaptureWidget),
// so the two look and read the same. The founder approved this layout on 2026-09-26.

struct TodoEntry: TimelineEntry {
    enum Content {
        /// Read on purpose from the corpus the app uses. `corpusID` travels into every
        /// Done button so a row can never archive in a different corpus (P6).
        case list(rows: [TodoWidgetList.Row], someUnreadable: Bool, corpusID: String)
        /// Could not read the list. Never shown as "Nothing to do" (D8).
        case unknown(reason: String)
    }

    let date: Date
    let content: Content
    /// Replaces the "Can't read" headline when there is a plainer thing to say
    /// (the phone's "locked" and "open the app once").
    var unknownHeadline: String? = nil

    /// The widget gallery's preview. Illustrative only; never real notes.
    static let sample = TodoEntry(date: Date(), content: .list(rows: [
        .init(id: UUID(), title: "Update the website link on the ClearSpace App Store page",
              subtitle: "Suggested by Claude · 3 days ago · clearspace"),
        .init(id: UUID(), title: "Delete old copies of the website so its hosting space stops being full",
              subtitle: "Suggested by Codex · yesterday · calmdownoscar"),
        .init(id: UUID(), title: "Add a rate-this-app prompt to Shuttle Vision",
              subtitle: "Suggested by Claude · today · badminton"),
    ], someUnreadable: false, corpusID: ""))
}

struct TodoWidgetView<DoneIntent: AppIntent>: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry
    /// The Done button's intent for one row (the row id, and the corpus it came from).
    let done: (UUID, String) -> DoneIntent
    /// Where the header and "+N more" go. Nil on the phone: tapping opens the app.
    var listURL: URL? = TodoLink.todo.url
    /// Where tapping a row goes. Nil on the phone.
    var rowURL: ((UUID) -> URL)? = { TodoLink.handoff($0).url }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .unknown(let reason):
            message(entry.unknownHeadline ?? TodoWidgetList.unknownText,
                    detail: reason.isEmpty ? nil : reason)
                .widgetURL(listURL)
        case .list(let rows, let someUnreadable, let corpusID):
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    header(count: 0)
                    message(TodoWidgetList.emptyText, detail: someUnreadable ? TodoWidgetList.someUnreadableText : nil)
                }
                .widgetURL(listURL)
            } else if family == .systemSmall {
                small(rows, someUnreadable: someUnreadable)
            } else {
                list(rows, someUnreadable: someUnreadable, corpusID: corpusID)
            }
        }
    }

    // MARK: - Pieces

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("To do")
                .font(.system(size: 13, weight: .bold))
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func message(_ text: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Small: how many, and the oldest one. The whole widget opens the To Do pane.
    private func small(_ rows: [TodoWidgetList.Row], someUnreadable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TodoWidgetList.countText(rows.count))
                .font(.system(size: 15, weight: .bold))
            Text(rows[0].title)
                .font(.system(size: 12))
                .lineLimit(4)
            Spacer(minLength: 0)
            Text(someUnreadable ? TodoWidgetList.someUnreadableText : rows[0].subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .widgetURL(listURL)
    }

    private func list(_ rows: [TodoWidgetList.Row], someUnreadable: Bool, corpusID: String) -> some View {
        let capacity = family == .systemLarge ? 6 : 3
        let shown = Array(rows.prefix(capacity))
        let hidden = rows.count - shown.count
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 9 : 6) {
            linked(listURL) { header(count: rows.count) }
            ForEach(shown) { row in
                rowView(row, corpusID: corpusID)
            }
            Spacer(minLength: 0)
            if hidden > 0 || someUnreadable {
                linked(listURL) {
                    Text(someUnreadable ? TodoWidgetList.someUnreadableText : TodoWidgetList.moreText(hidden))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One item: a Done circle (like Reminders) and, beside it, the item itself, which
    /// opens the handoff it came from.
    private func rowView(_ row: TodoWidgetList.Row, corpusID: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Button(intent: done(row.id, corpusID)) {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodoWidgetList.markDoneLabel(row.title))

            linked(rowURL?(row.id)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(family == .systemLarge ? 2 : 1)
                    Text(row.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Redacted on a locked iPhone's Lock Screen and in StandBy.
                .privacySensitive()
            }
        }
    }

    /// Wraps content in a Link when there is somewhere to go; the phone widget has none,
    /// so a tap there simply opens Capture.
    @ViewBuilder
    private func linked<Content: View>(_ url: URL?, @ViewBuilder _ content: () -> Content) -> some View {
        if let url {
            Link(destination: url) { content() }
        } else {
            content()
        }
    }
}
