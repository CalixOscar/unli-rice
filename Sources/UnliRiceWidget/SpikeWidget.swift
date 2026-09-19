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
                    status = "Notes: \(notes.count) · peak \(Self.peakFootprintMB()) · run \(Date().formatted(date: .omitted, time: .standard))"
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

    /// B0 diagnostic: this process's peak physical footprint so far, as the kernel's
    /// ledger records it — the figure the 30 MB stop line in the plan is about. The run
    /// time beside it shows the number came from a fresh run, not a cached rendering.
    static func peakFootprintMB() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return "unknown" }
        return String(format: "%.1f MB", Double(info.ledger_phys_footprint_peak) / 1_048_576)
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
