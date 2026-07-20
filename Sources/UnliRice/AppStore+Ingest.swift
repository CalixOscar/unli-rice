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
        Pipelines.standard(scanRoots: scanRoots)
    }

    private var rawStore: RawStore {
        RawStore(directoryURL: RawStore.directoryURL(besideEventLog: dataURL))
    }

    /// What the pipelines would pull in. Writes nothing and copies nothing.
    func previewIngest() async {
        guard !ingestBusy else { return }
        ingestBusy = true
        defer { ingestBusy = false }

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

    func addScanRoot(_ folder: URL) {
        guard !scanRoots.contains(folder) else { return }
        scanRoots.append(folder)
    }

    func removeScanRoot(_ folder: URL) {
        scanRoots.removeAll { $0 == folder }
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
