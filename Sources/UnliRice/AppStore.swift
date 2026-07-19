import AppKit
import Foundation
import UnliRiceCore
import UnliRiceMLX
import UniformTypeIdentifiers

/// The view-model backing the whole window. Talks to `NoteService` directly —
/// this is a first-party client of the same event log the MCP server and any
/// connected LLM agent read and write, not a separate copy of the data.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var archivedNotes: [Note] = []
    @Published private(set) var pending: [(note: Note, flag: ReviewFlag)] = []

    /// The same queue, grouped into the decisions a person actually faces — see
    /// `ReviewQueue.cluster`. What `JanitorControls`/`AutonomyPanel` render.
    ///
    /// Passes `note(id:)` — which resolves against `noteIndex`, not just the
    /// pending set — because a duplicate flag lives on only one side of a pair;
    /// the older note in a chain needs to be found by id even though it carries
    /// no flag of its own.
    var pendingClusters: [ReviewCluster] {
        ReviewQueue.cluster(pending.map { ReviewItem(note: $0.note, flag: $0.flag) }) { self.note(id: $0) }
    }
    @Published var visibleCount: Int = 5
    @Published var statusMessage: String = "Showing: last 5 updated notes (default view)."
    @Published var errorMessage: String?
    @Published var autonomyLevel: Int {
        didSet { UserDefaults.standard.set(autonomyLevel, forKey: Self.autonomyKey) }
    }

    /// The note shown in the detail pane, if any. Cleared automatically if the
    /// selected note is archived out of the default list — see `reload()`.
    @Published var selectedNoteID: UUID?
    @Published var showingArchived: Bool = false
    @Published var showingAssistant: Bool = false
    @Published var showingReviewQueue: Bool = false

    // MARK: - Janitor (see AppStore+Janitor.swift)

    /// What the janitor *would* do, from the last preview. Empty after a real
    /// run, since the proposals have by then become tags and queued flags.
    @Published var janitorPreview: [JanitorProposal] = []
    @Published var janitorSummary: String?
    @Published var janitorBusy: Bool = false
    @Published var similarityEngine: SimilarityEngine = .tokenOverlap

    /// Loaded lazily on first janitor use and kept for the session — the model
    /// costs seconds to load and nothing at all to hold.
    var mlxSimilarity: MLXSimilarity?

    // MARK: - Chat (see AppStore+Chat.swift)

    @Published var chatHistory: [ChatTurn] = []
    @Published var chatBusy: Bool = false
    @Published var chatEngineStatus: ChatEngineStatus = .notLoaded

    /// Per-cluster duplicate recommendations, keyed by `ReviewCluster.id`.
    /// `"…"` while a request is in flight; cleared on `reload()` since a
    /// cluster's identity (and membership) can change once its flags are
    /// resolved or a new run adds more.
    @Published var clusterRecommendations: [String: String] = [:]

    var janitorChat: JanitorChat?

    private static let autonomyKey = "unliRice.autonomyLevel"
    private static let onboardingSeededKey = "unliRice.didSeedOnboardingNotes"
    let service: NoteService
    let dataURL: URL

    /// Every known note (active or archived) by id, refreshed on every `reload()`.
    /// Exists so the detail view can resolve a wiki-link's target — including one
    /// that's archived — without a second round trip through `NoteService`.
    private var noteIndex: [UUID: Note] = [:]

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

        // GUI-only, deliberately: an agent connecting over MCP before any human
        // has ever opened the app should never find two mystery notes it didn't
        // write. Onboarding is a first-*window* concern, not a first-*write*
        // concern, so this stays out of unlirice-mcp entirely.
        do {
            try Onboarding.seedIfNeeded(
                service: service,
                hasSeeded: { UserDefaults.standard.bool(forKey: Self.onboardingSeededKey) },
                markSeeded: { UserDefaults.standard.set(true, forKey: Self.onboardingSeededKey) }
            )
        } catch {
            // A failed seed leaves an empty-but-explained-by-nothing list, which
            // is worse UX than silence but not worth blocking launch over.
        }

        reload()
    }

    /// Same resolution as unlirice-mcp — both go through `DataLocation`, so the
    /// GUI and any connected agent are always reading and writing the same file.
    static func defaultDataFileURL() -> URL {
        DataLocation.eventLogURL()
    }

    func reload() {
        do {
            let all = try service.listNotes(includeArchived: true)
            noteIndex = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            notes = all.filter { !$0.archived }
            archivedNotes = all.filter { $0.archived }
            pending = try service.pendingReviews()
            // Drop cached recommendations for clusters that no longer exist —
            // a cluster's id is derived from union-find over its member ids, so
            // resolving one flag in a group (or a new run adding another) can
            // legitimately produce a different id for what's conceptually "the
            // same" pile. Worst case a live cluster loses its cached answer and
            // re-asks; better than showing a stale answer under a stale key.
            let liveClusterIDs = Set(pendingClusters.map(\.id))
            clusterRecommendations = clusterRecommendations.filter { liveClusterIDs.contains($0.key) }
            errorMessage = nil
            if let selected = selectedNoteID, noteIndex[selected] == nil {
                selectedNoteID = nil
            }
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Looks up any known note by id — active or archived — for resolving a
    /// wiki-link target or a backlink in the detail view.
    func note(id: UUID) -> Note? {
        noteIndex[id]
    }

    var selectedNote: Note? {
        selectedNoteID.flatMap { noteIndex[$0] }
    }

    var visibleNotes: [Note] {
        let source = showingArchived ? archivedNotes : notes
        return visibleCount == 0 ? [] : Array(source.prefix(visibleCount))
    }

    func showLatest() {
        showingArchived = false
        showingAssistant = false
        showingReviewQueue = false
        visibleCount = 1
        statusMessage = "Showing: the single most recently updated note."
    }

    func showLast(_ n: Int) {
        showingArchived = false
        showingAssistant = false
        showingReviewQueue = false
        visibleCount = n
        statusMessage = "Showing: last \(n) updated notes."
    }

    func showAllNotes() {
        showLast(visibleCount == 0 ? 5 : visibleCount)
    }

    func showArchived() {
        showingArchived = true
        showingAssistant = false
        showingReviewQueue = false
        visibleCount = 50
        statusMessage = archivedNotes.isEmpty
            ? "No archived notes."
            : "Showing \(archivedNotes.count) archived note\(archivedNotes.count == 1 ? "" : "s")."
    }

    /// The chat panel — see `AppStore+Chat.swift`. Advisory only: nothing said
    /// here changes a note, same as the janitor's own proposals.
    func showAssistant() {
        showingArchived = false
        showingAssistant = true
        showingReviewQueue = false
        statusMessage = "Local assistant — advisory only. Nothing it says changes a note without your say."
    }

    /// The review queue, full width in the main column — not the narrow
    /// right-hand panel it used to live in. A pile of near-duplicate notes
    /// needs room for full titles and an actual "Keep this one" button per
    /// note; 260pt of sidebar was cramping both into truncated text.
    func showReviewQueue() {
        showingArchived = false
        showingAssistant = false
        showingReviewQueue = true
        statusMessage = pending.isEmpty
            ? "Nothing is waiting on you right now."
            : "\(pending.count) item\(pending.count == 1 ? "" : "s") waiting for your OK."
    }

    func selectNote(_ id: UUID?) {
        selectedNoteID = id
        if id != nil {
            showingAssistant = false
            showingReviewQueue = false
        }
    }

    @discardableResult
    func createNote(title: String, body: String = "") -> Note? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let created = try service.createNote(title: trimmed, body: body, source: "human")
            reload()
            return created
        } catch {
            errorMessage = "\(error)"
            return nil
        }
    }

    /// The action that turns a one-shot capture into an actual memory: adding to
    /// something already written, rather than only ever starting something new.
    func append(to note: Note, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try service.appendToNote(id: note.id, text: trimmed, source: "human")
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func addTag(_ tag: String, to note: Note) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try service.tagNote(id: note.id, tag: trimmed, source: "human")
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func removeTag(_ tag: String, from note: Note) {
        do {
            _ = try service.untagNote(id: note.id, tag: tag, source: "human")
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Soft and reversible, mirroring `NoteService.archiveNote` — see
    /// PROJECT_NOTES.md on why there is no hard-delete anywhere in this app.
    func archive(_ note: Note, reason: String = "archived from Unli Rice") {
        do {
            _ = try service.archiveNote(id: note.id, reason: reason, source: "human")
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func unarchive(_ note: Note) {
        do {
            _ = try service.unarchiveNote(id: note.id, source: "human")
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

    /// One answer, applied to every flag in a cluster.
    ///
    /// This is presentation collapsing, not permission collapsing: it still
    /// calls `resolveReview` once per underlying flag, so the event log ends up
    /// exactly as it would if you'd clicked each one — just without making you
    /// click each one. A duplicate group answered "reject" also won't be
    /// re-raised, because each flag's own fingerprint stamp is what
    /// `JanitorRunner` checks, and every flag in the group gets stamped.
    func resolve(cluster: ReviewCluster, outcome: String) {
        do {
            for item in cluster.items {
                _ = try service.resolveReview(
                    id: item.note.id, flagId: item.flag.id, source: "human", outcome: outcome
                )
            }
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// "Keep this one" on a duplicate cluster: merges the others' content onto
    /// `keeper` and archives them, then clears every flag in the cluster.
    /// Nothing here runs unattended — this exists specifically because
    /// Accept/Reject alone changed nothing about the notes themselves, which
    /// left a real gap between what the buttons implied and what actually
    /// happened. See `NoteService.consolidateDuplicates`.
    func consolidate(cluster: ReviewCluster, keeping keeper: Note) {
        do {
            let others = cluster.notes.map(\.id).filter { $0 != keeper.id }
            let flags = cluster.items.map { (noteID: $0.note.id, flagID: $0.flag.id) }
            _ = try service.consolidateDuplicates(
                keeping: keeper.id, archiving: others, resolving: flags, source: "human"
            )
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
