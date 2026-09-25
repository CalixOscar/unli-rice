import SwiftUI
import UnliRiceCore
import WidgetKit

@main
struct UnliRiceTodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoWidgetList.kind, provider: TodoTimelineProvider()) { entry in
            TodoWidgetView(entry: entry) { id, corpus in
                MarkTodoDoneIntent(noteID: id, corpusID: corpus)
            }
        }
        .configurationDisplayName("To do")
        .description("Things your AI assistants suggested doing later.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
