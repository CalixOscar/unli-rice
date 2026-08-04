import Foundation

/// Service that exports derived Markdown files into a mirror directory (`<Profile Name> Export/`)
/// for cold-start LLMs or tools that do not use MCP.
public enum MirrorExporter {
    public static let memoryCapsuleTitle = "Memory: capsule"
    public static let maxMemoryCapsuleChars = 2500

    public struct ExportResult: Sendable {
        public let exportDirectoryURL: URL
        public let exportedFilesCount: Int
        public let generatedAt: Date
        public let memoryCapsuleLength: Int?
        public let memoryCapsuleExceeded: Bool
    }

    /// Exports the current profile's derived context files.
    @discardableResult
    public static func exportMirror(
        profileName: String,
        vaultFolderURL: URL,
        noteService: NoteService,
        houseRulesText: String? = nil,
        customExportDirectory: URL? = nil
    ) throws -> ExportResult {
        let exportDir: URL
        if let custom = customExportDirectory {
            exportDir = custom
        } else {
            let parentDir = vaultFolderURL.deletingLastPathComponent()
            let safeName = profileName.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespaces)
            exportDir = parentDir.appendingPathComponent("\(safeName) Export", isDirectory: true)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        var exportedCount = 0
        let notes = try noteService.listNotes(includeArchived: false)

        // Exact title match, not prefix: ProfileBuilder writes these exact
        // titles, and a prefix would let a user note like "Profile: identity —
        // old draft" shadow the real one depending on list order.
        func latestNoteBody(titled title: String) -> String? {
            notes.first(where: { $0.title.lowercased() == title.lowercased() })?.body
        }

        let numberedFiles: [(String, String)] = [
            ("00_Index.md", "Profile: index"),
            ("01_Identity.md", "Profile: identity"),
            ("02_Voice.md", "Profile: voice"),
            ("03_Principles.md", "Profile: principles"),
            ("04_Guardrails.md", "Profile: guardrails"),
        ]
        for (filename, title) in numberedFiles {
            if let body = latestNoteBody(titled: title) {
                try writeExportFile(filename: filename, content: body, in: exportDir)
                exportedCount += 1
            }
        }

        // 05+_Overlay_<Name>.md — numbered after the core set, matching the
        // folder convention this feature is modeled on.
        let overlayPrefix = "profile: overlay "
        let overlayNotes = notes
            .filter { $0.title.lowercased().hasPrefix(overlayPrefix) }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
        for (index, note) in overlayNotes.enumerated() {
            let name = safeFilenameComponent(String(note.title.dropFirst(overlayPrefix.count))).capitalized
            let filename = String(format: "%02d_Overlay_%@.md", 5 + index, name)
            try writeExportFile(filename: filename, content: note.body, in: exportDir)
            exportedCount += 1
        }

        // PROJECTS/<name>.md — one file per `Project:` note.
        let projectPrefix = "project: "
        let projectNotes = notes
            .filter { $0.title.lowercased().hasPrefix(projectPrefix) }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
        if !projectNotes.isEmpty {
            let projectsDir = exportDir.appendingPathComponent("PROJECTS", isDirectory: true)
            try fileManager.createDirectory(at: projectsDir, withIntermediateDirectories: true)
            for note in projectNotes {
                let name = safeFilenameComponent(String(note.title.dropFirst(projectPrefix.count)))
                try writeExportFile(filename: "\(name).md", content: note.body, in: projectsDir)
                exportedCount += 1
            }
        }

        // MEMORY.md capsule
        var capsuleLen: Int? = nil
        var capsuleExceeded = false
        if let capsuleNote = notes.first(where: { $0.title.lowercased() == memoryCapsuleTitle.lowercased() }) {
            let body = capsuleNote.body
            capsuleLen = body.count
            capsuleExceeded = body.count > maxMemoryCapsuleChars
            try writeExportFile(filename: "MEMORY.md", content: body, in: exportDir)
            exportedCount += 1
        }

        // HOUSE_RULES.md
        if let houseRules = houseRulesText, !houseRules.isEmpty {
            try writeExportFile(filename: "HOUSE_RULES.md", content: houseRules, in: exportDir)
            exportedCount += 1
        }

        // RAW/ folder mirroring
        let rawSourceURL = vaultFolderURL.appendingPathComponent("raw", isDirectory: true)
        let rawTargetURL = exportDir.appendingPathComponent("RAW", isDirectory: true)
        if fileManager.fileExists(atPath: rawSourceURL.path) {
            try? fileManager.removeItem(at: rawTargetURL)
            try? fileManager.copyItem(at: rawSourceURL, to: rawTargetURL)
        }

        // CLAUDE.md and AGENTS.md — convention files for Vault Mode
        let noteCountStr = "\(notes.count) note\(notes.count == 1 ? "" : "s")"
        let contextNote: String
        if Autopilot.detectedPackageRoot() != nil || !projectNotes.isEmpty {
            contextNote = "Unli Rice notes supplement instructions for this project."
        } else {
            contextNote = "No project folder here — Unli Rice notes are your only context for this session."
        }

        let conventionContent = """
        # Unli Rice vault — \(noteCountStr), profile "\(profileName)"

        You are connected to Unli Rice. These notes are the user's memory. \(contextNote)

        Start here: `Wiki: index.md` (or `00_Index.md`), then grep this folder for the topic at hand.

        Open your first reply with exactly:
        ✅ Unli Rice vault connected — \(noteCountStr), profile "\(profileName)".
        If you found no relevant notes, say so instead. Never claim otherwise.
        """

        try writeExportFile(filename: "CLAUDE.md", content: conventionContent, in: exportDir)
        exportedCount += 1
        try writeExportFile(filename: "AGENTS.md", content: conventionContent, in: exportDir)
        exportedCount += 1

        return ExportResult(
            exportDirectoryURL: exportDir,
            exportedFilesCount: exportedCount,
            generatedAt: Date(),
            memoryCapsuleLength: capsuleLen,
            memoryCapsuleExceeded: capsuleExceeded
        )
    }

    private static func safeFilenameComponent(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func writeExportFile(filename: String, content: String, in directory: URL) throws {
        let fileURL = directory.appendingPathComponent(filename)
        let data = Data(content.utf8)
        try data.write(to: fileURL, options: .atomic)
    }
}
