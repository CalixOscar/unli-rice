import SwiftUI
import UnliRiceCore
import WidgetKit

@main
struct UnliRiceTodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoWidgetList.kind, provider: TodoTimelineProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("To do")
        .description("Things your AI assistants suggested doing later.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodoEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .unknown(let reason):
            message(TodoWidgetList.unknownText, detail: reason)
                .widgetURL(TodoLink.todo.url)
        case .list(let rows, let someUnreadable, let corpusID):
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    header(count: 0)
                    message(TodoWidgetList.emptyText, detail: someUnreadable ? TodoWidgetList.someUnreadableText : nil)
                }
                .widgetURL(TodoLink.todo.url)
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
        .widgetURL(TodoLink.todo.url)
    }

    private func list(_ rows: [TodoWidgetList.Row], someUnreadable: Bool, corpusID: String) -> some View {
        let capacity = family == .systemLarge ? 6 : 3
        let shown = Array(rows.prefix(capacity))
        let hidden = rows.count - shown.count
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 9 : 6) {
            Link(destination: TodoLink.todo.url) { header(count: rows.count) }
            ForEach(shown) { row in
                rowView(row, corpusID: corpusID)
            }
            Spacer(minLength: 0)
            if hidden > 0 || someUnreadable {
                Link(destination: TodoLink.todo.url) {
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
            Button(intent: MarkTodoDoneIntent(noteID: row.id, corpusID: corpusID)) {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodoWidgetList.markDoneLabel(row.title))

            Link(destination: TodoLink.handoff(row.id).url) {
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
            }
        }
    }
}
