import AppKit
import Foundation
import UnliRiceCore
import UnliRiceHost

/// The data pipelines, and the routine loop that can run them unattended.
///
/// The same shape as `AppStore+Janitor.swift`, and for the same reason: preview
/// is offered first and reads as the default action. It matters more here —
/// these importers read the user's own files, so "show me what you'd take"
/// before "take it" isn't a nicety, it's the whole basis for trusting the
/// feature enough to leave it on a schedule.
extension AppStore {
    /// Every pipeline that currently has somewhere to look.
    ///
    /// `LocalFileImporter` is omitted entirely when no folder has been
    /// nominated, rather than included and returning nothing: there is no
    /// default root by design, and a pipeline listed as active while scanning
    /// nowhere is a lie the UI would be telling.
    /// The same list the background agent runs — see `Pipelines.standard`.
    /// Assembling it here as well would mean the scheduled run could quietly
    /// differ from the button.
    var importers: [ResourceImporter] {
        Pipelines.standard(scanRoots: scanRoots, claudeProjectsDirectory: claudeProjectsURL)
    }

    private var rawStore: RawStore {
        RawStore(directoryURL: RawStore.directoryURL(besideEventLog: dataURL))
    }

    /// What the pipelines would pull in. Writes nothing and copies nothing.
    func previewIngest() async {
        guard !ingestBusy else { return }
        ingestBusy = true
        defer { ingestBusy = false }

        let activeRoots = scanRoots.map { ($0, $0.startAccessingSecurityScopedResource()) }
        let activeClaude = claudeProjectsURL.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer {
            for (url, started) in activeRoots { if started { url.stopAccessingSecurityScopedResource() } }
            if let (url, started) = activeClaude, started { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let runner = IngestRunner(service: service, rawStore: rawStore)
            var found: [DiscoveredResource] = []
            for importer in importers {
                found.append(contentsOf: try runner.preview(importer: importer))
            }
            ingestPreview = found
            ingestSummary = found.isEmpty
                ? "Nothing found to ingest. \(scanRoots.isEmpty ? "No document folders have been added yet." : "")"
                : "\(found.count) resource\(found.count == 1 ? "" : "s") found. Nothing has been copied or indexed."
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Copies resources into `/raw` and writes one index note each.
    ///
    /// It cannot do more than that: `IngestRunner` calls only `createNote`,
    /// `appendToNote` and `tagNote`, and never touches a note it didn't author.
    /// Nothing here could widen that even if it tried to — the restriction lives
    /// in the runner, not in this method.
    @discardableResult
    func runIngestNow() async -> Bool {
        guard !ingestBusy else { return false }
        ingestBusy = true
        defer { ingestBusy = false }

        let activeRoots = scanRoots.map { ($0, $0.startAccessingSecurityScopedResource()) }
        let activeClaude = claudeProjectsURL.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer {
            for (url, started) in activeRoots { if started { url.stopAccessingSecurityScopedResource() } }
            if let (url, started) = activeClaude, started { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let runner = IngestRunner(service: service, rawStore: rawStore)
            var summaries: [String] = []
            for importer in importers {
                summaries.append(try runner.run(importer: importer).summary)
            }
            ingestPreview = []
            ingestSummary = summaries.joined(separator: " · ")
            reload()
            return true
        } catch {
            errorMessage = "\(error)"
            return false
        }
    }

    /// Nominating a folder is the *only* way the local-document pipeline gets
    /// anything to look at. Deliberately a picker rather than a text field or a
    /// default: the user sees exactly which folder they granted, one at a time.
    func chooseScanRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to index"
        panel.message = "Markdown and text documents in this folder are copied into your raw store and indexed. Source code is skipped."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Index This Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        addScanRoot(folder)
    }

    /// Any folder is allowed — Documents, Desktop, a vault, one project. The
    /// only thing enforced is that roots don't nest inside one another; see
    /// `ScanRoots` for why that matters more than it looks.
    func addScanRoot(_ folder: URL) {
        let change = ScanRoots.adding(folder, to: scanRoots)

        guard change.didChange else {
            statusMessage = """
            \(folder.lastPathComponent) is already covered by \
            \(change.alreadyCoveredBy?.lastPathComponent ?? "an existing folder") — \
            folders are searched all the way down.
            """
            return
        }

        scanRoots = change.roots
        let baseStatus = change.removed.isEmpty
            ? "Indexing \(folder.lastPathComponent)."
            : """
            Indexing \(folder.lastPathComponent) — it contains \
            \(change.removed.map(\.lastPathComponent).joined(separator: ", ")), \
            so \(change.removed.count == 1 ? "that folder is" : "those folders are") \
            no longer listed separately.
            """

        statusMessage = baseStatus

        // Automatic preview & prompt to import notes immediately
        let importer = LocalFileImporter(
            roots: [folder],
            maximumDepth: 20,
            maximumFilesPerRoot: 10000,
            minimumBytes: 0
        )

        do {
            let discovered = try importer.discover()
            guard !discovered.isEmpty else {
                statusMessage = "\(baseStatus) No importable prose documents found."
                return
            }

            let count = discovered.count
            let alert = NSAlert()

            if count > 50 {
                alert.alertStyle = .warning
                alert.messageText = "Import \(count) notes from “\(folder.lastPathComponent)”?"
                alert.informativeText = """
                Unli Rice found \(count) prose documents in this folder.

                Warning: Importing this many files will write many entries to your permanent, append-only event log.

                Are you sure you want to proceed?
                """
                alert.addButton(withTitle: "Import Anyway")
                alert.addButton(withTitle: "Cancel")
            } else {
                alert.alertStyle = .informational
                alert.messageText = "Import \(count) note\(count == 1 ? "" : "s") from “\(folder.lastPathComponent)”?"
                alert.informativeText = "Unli Rice found \(count) prose document\(count == 1 ? "" : "s") ready to be imported."
                alert.addButton(withTitle: "Import")
                alert.addButton(withTitle: "Cancel")
            }

            if alert.runModal() == .alertFirstButtonReturn {
                let runner = IngestRunner(service: service, rawStore: rawStore)
                let report = try runner.run(importer: importer)
                reload()
                statusMessage = report.summary
            } else {
                statusMessage = "\(baseStatus) Automatic import cancelled. Folder added to scan roots."
            }
        } catch {
            errorMessage = "Failed to preview \(folder.lastPathComponent): \(error)"
        }
    }

    func removeScanRoot(_ folder: URL) {
        scanRoots.removeAll { $0 == folder }
    }

    func chooseClaudeProjectsFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Claude projects folder"
        panel.message = "Under App Sandbox, Unli Rice needs permission to read your Claude Code projects directory. Pick ~/.claude/projects."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        panel.prompt = "Grant Access"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        do {
            let bookmarkData = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: "unliRice.claudeProjectsBookmark")
            claudeProjectsURL = folder
            statusMessage = "Access granted to Claude projects folder."
        } catch {
            errorMessage = "Failed to create bookmark for Claude projects folder: \(error)"
        }
    }

    func removeClaudeProjectsFolder() {
        UserDefaults.standard.removeObject(forKey: "unliRice.claudeProjectsBookmark")
        claudeProjectsURL = nil
        statusMessage = "Claude Code session access removed."
    }

    // MARK: - The routine loop

    /// The in-window heartbeat, now a thin wrapper over the same
    /// `RoutineDriver` the background agent runs.
    ///
    /// This method used to *be* the automation, which is why closing the window
    /// stopped it. It's kept because the window being open is still a perfectly
    /// good moment to serve a due slot, and because someone who hasn't installed
    /// the background agent should still get routines while they're here.
    ///
    /// Double-running is not a concern: both paths go through
    /// `RoutineRunLock` and the shared `RoutineState` file, so whichever process
    /// gets there first serves the slot and the other finds it served.
    func tickRoutines() async {
        let report = routineDriver.tick(
            settings: agentSettings,
            machine: MachineState.current(),
            similarity: TokenOverlapSimilarity()
        )
        if report.didWork {
            ingestSummary = report.ran.first { $0.kind == .dataIngestion }?.summary ?? ingestSummary
            janitorSummary = report.ran.first { $0.kind == .systemImprovement }?.summary ?? janitorSummary
            reload()
        } else if !report.posted.isEmpty {
            refreshNotices()
        }
    }

    func lastRun(of kind: RoutineKind) -> Date? {
        RoutineState.load(from: RoutineState.url(besideEventLog: dataURL)).lastRun(of: kind)
    }
}
