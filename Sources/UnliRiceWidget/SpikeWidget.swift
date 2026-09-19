import WidgetKit
import SwiftUI
import UnliRiceCore

struct SpikeEntry: TimelineEntry {
    let date: Date
    let statusText: String
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: Date(), statusText: "Placeholder")
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func fetchEntry() -> SpikeEntry {
        let status: String
        switch WidgetCorpus.resolve() {
        case .success(let resolved):
            do {
                let store = try EventStore(readingExisting: resolved.log)
                let service = NoteService(store: store)
                if let notes = try? service.listNotes(includeArchived: false) {
                    status = "Notes: \(notes.count)"
                } else {
                    status = "logUnreadable"
                }
            } catch {
                status = "logUnreadable"
            }
        case .failure(let reason):
            status = "\(reason)"
        }
        return SpikeEntry(date: Date(), statusText: status)
    }
}

struct SpikeEntryView: View {
    var entry: SpikeProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unli Rice Spike")
                .font(.headline)
            Text(entry.statusText)
                .font(.body)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct SpikeWidget: Widget {
    let kind: String = "UnliRiceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SpikeProvider()) { entry in
            SpikeEntryView(entry: entry)
        }
        .configurationDisplayName("Unli Rice Spike")
        .description("Spike widget for WidgetCorpus testing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
