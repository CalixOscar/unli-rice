import Foundation

public enum ExportFormat: String, CaseIterable, Sendable {
    case markdown
    case okfBundle
    case zip
    case pdf

    public var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .okfBundle: return "OKF Bundle"
        case .zip: return "Zip"
        case .pdf: return "PDF"
        }
    }

    /// True for formats that write a directory rather than a single file.
    public var isDirectory: Bool {
        self == .okfBundle
    }
}

/// One-way, read-only export: everything here is rendered fresh from
/// `NoteService`'s existing read methods. Export never becomes a second
/// source of truth — the event log stays authoritative (see PROJECT_NOTES.md).
public enum ExportService {
    public static func export(
        using service: NoteService,
        format: ExportFormat,
        to destination: URL,
        includeArchived: Bool = false
    ) throws {
        let notes = try service.listNotes(includeArchived: includeArchived)

        switch format {
        case .markdown:
            let text = MarkdownRenderer.renderCombined(notes)
            try text.write(to: destination, atomically: true, encoding: .utf8)

        case .pdf:
            #if os(macOS)
            let data = PDFExporter.renderCombined(notes)
            try data.write(to: destination)
            #else
            break
            #endif

        case .okfBundle:
            let events = try service.transactionLog(limit: .max)
            try OKFExporter.exportBundle(notes: notes, events: events, to: destination)

        case .zip:
            let events = try service.transactionLog(limit: .max)
            // Two-level temp path: a UUID'd parent avoids collisions, but the
            // actual bundle folder keeps a clean name, so the archive expands
            // into "Unli Rice Export" rather than a raw UUID.
            let tempParent = FileManager.default.temporaryDirectory
                .appendingPathComponent("unlirice-export-\(UUID().uuidString)")
            let bundleDir = tempParent.appendingPathComponent("Unli Rice Export")
            try OKFExporter.exportBundle(notes: notes, events: events, to: bundleDir)
            defer { try? FileManager.default.removeItem(at: tempParent) }
            try ZipExporter.zip(directory: bundleDir, to: destination)
        }
    }
}
