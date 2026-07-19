import AppKit
import Foundation
import SecondBrainCore
import UniformTypeIdentifiers

/// The view-model backing the whole window. Talks to `NoteService` directly —
/// this is a first-party client of the same event log the MCP server and any
/// connected LLM agent read and write, not a separate copy of the data.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var pending: [(note: Note, flag: ReviewFlag)] = []
    @Published var visibleCount: Int = 5
    @Published var statusMessage: String = "Showing: last 5 updated notes (default view)."
    @Published var errorMessage: String?
    @Published var autonomyLevel: Int {
        didSet { UserDefaults.standard.set(autonomyLevel, forKey: Self.autonomyKey) }
    }

    private static let autonomyKey = "unliRice.autonomyLevel"
    private let service: NoteService
    let dataURL: URL

    init() {
        let url = AppStore.defaultDataFileURL()
        dataURL = url
        autonomyLevel = UserDefaults.standard.object(forKey: AppStore.autonomyKey) as? Int ?? 1
        do {
            let store = try EventStore(fileURL: url)
            service = NoteService(store: store)
        } catch {
            fatalError("Could not open event log at \(url.path): \(error)")
        }
        reload()
    }

    /// Same default + override rule as secondbrain-mcp, so the GUI and any
    /// connected agent are always reading and writing the same file.
    static func defaultDataFileURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["SECONDBRAIN_DATA_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SecondBrain", isDirectory: true).appendingPathComponent("events.jsonl")
    }

    func reload() {
        do {
            notes = try service.listNotes()
            pending = try service.pendingReviews()
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }

    var visibleNotes: [Note] {
        visibleCount == 0 ? [] : Array(notes.prefix(visibleCount))
    }

    func showLatest() {
        visibleCount = 1
        statusMessage = "Showing: the single most recently updated note."
    }

    func showLast(_ n: Int) {
        visibleCount = n
        statusMessage = "Showing: last \(n) updated notes."
    }

    func showWaiting() {
        visibleCount = 0
        statusMessage = pending.isEmpty
            ? "Nothing updated is waiting on you — check the Review Queue for open proposals."
            : "\(pending.count) item\(pending.count == 1 ? "" : "s") waiting in the Review Queue."
    }

    func createNote(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try service.createNote(title: trimmed, body: "", source: "human")
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Every structural resolution goes through this — the autonomy slider never
    /// bypasses it, regardless of position. See PROJECT_NOTES.md.
    func resolve(note: Note, flag: ReviewFlag, outcome: String) {
        do {
            _ = try service.resolveReview(id: note.id, flagId: flag.id, source: "human", outcome: outcome)
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: - Export

    /// Prompts for a destination (file for markdown/pdf/zip, folder for the
    /// OKF bundle) and writes it. One-way, read-only — see ExportService.
    func exportNotes(as format: ExportFormat) {
        if format.isDirectory {
            let panel = NSOpenPanel()
            panel.title = "Choose a folder for the OKF export"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export"
            guard panel.runModal() == .OK, let folder = panel.url else { return }
            let bundleURL = folder.appendingPathComponent("Unli Rice Export")
            performExport(format: format, to: bundleURL)
        } else {
            let panel = NSSavePanel()
            panel.title = "Export Notes"
            panel.nameFieldStringValue = defaultFileName(for: format)
            panel.allowedContentTypes = [contentType(for: format)]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            performExport(format: format, to: url)
        }
    }

    private func performExport(format: ExportFormat, to url: URL) {
        do {
            try ExportService.export(using: service, format: format, to: url)
            statusMessage = "Exported \(notes.count) note\(notes.count == 1 ? "" : "s") as \(format.displayName) → \(url.lastPathComponent)"
        } catch {
            errorMessage = "Export failed: \(error)"
        }
    }

    private func defaultFileName(for format: ExportFormat) -> String {
        switch format {
        case .markdown: return "Unli Rice Export.md"
        case .pdf: return "Unli Rice Export.pdf"
        case .zip: return "Unli Rice Export.zip"
        case .okfBundle: return "Unli Rice Export"
        }
    }

    private func contentType(for format: ExportFormat) -> UTType {
        switch format {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .pdf: return .pdf
        case .zip: return .zip
        case .okfBundle: return .folder
        }
    }
}
