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
    @Published var showingGraph: Bool = false
    @Published var showingGetStarted: Bool = false

    // MARK: - Get Started / Autopilot (see AppStore+Autopilot.swift)

    /// Which step of Get Started is on screen.
    @Published var setupStage: SetupStage = .start

    /// On by default. Governs only whether the house-rules note gets written —
    /// connecting an MCP client is required either way, since an unconnected
    /// note store is the problem this whole flow exists to solve.
    @Published var autopilotEnabled: Bool = true

    /// Targets the user has ticked, by `MCPTarget.id`.
    @Published var selectedTargetIDs: Set<String> = []

    /// Project folders for project-scoped targets (Claude Code, Antigravity),
    /// keyed by target id. There is no correct folder to guess here — both
    /// tools scope MCP servers per project.
    @Published var targetProjectFolders: [String: URL] = [:]

    /// Extra targets the user added by hand, for tools not in the catalog.
    @Published var customTargets: [MCPTarget] = []

    /// What happened for each target, once Connect has run.
    @Published var connectionResults: [ConnectionResult] = []

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

    /// The folder the user pointed the app at, if they ever did. A plain path
    /// is enough — this target ships no sandbox entitlement, so there's no
    /// security-scoped bookmark to keep alive across launches.
    static let dataFolderKey = "unliRice.dataFolderPath"

    /// Set once the user has finished, skipped, or otherwise dealt with Get
    /// Started. Without it, someone who generates a setup prompt but doesn't
    /// write a note gets the wizard again on every launch — the same
    /// resurfacing problem `Onboarding.seedIfNeeded`'s flag already solves for
    /// the seeded guides.
    private static let getStartedDoneKey = "unliRice.didCompleteGetStarted"

    /// Reassigned by `switchDataFolder(to:)` — the whole point of the "I
    /// already have a vault" path is that the corpus is not fixed at launch.
    private(set) var service: NoteService
    private(set) var dataURL: URL

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

        // Open on Get Started for someone who has nothing of their own yet —
        // the seeded guides don't count, since they arrived without the user
        // doing anything. Suppressed once they've dealt with the wizard, so
        // generating a setup prompt and closing the app doesn't bring it back.
        showingGetStarted = !hasUserAuthoredNotes
            && !UserDefaults.standard.bool(forKey: Self.getStartedDoneKey)
    }

    /// Whether anything in this corpus was written by a person or an agent, as
    /// opposed to arriving from `Onboarding.seedIfNeeded`.
    var hasUserAuthoredNotes: Bool {
        (notes + archivedNotes).contains { !$0.sources.isSubset(of: [Onboarding.source]) }
    }

    /// Same resolution as unlirice-mcp — both go through `DataLocation`, so the
    /// GUI and any connected agent are always reading and writing the same file.
    /// A folder the user chose is honoured here; `UNLIRICE_DATA_PATH` still
    /// outranks it, so tests and smoke runs can't be redirected into a real
    /// vault by a stale preference.
    static func defaultDataFileURL() -> URL {
        DataLocation.eventLogURL(
            persistedFolderPath: UserDefaults.standard.string(forKey: dataFolderKey)
        )
    }

    /// Points the app at a different folder's `events.jsonl` — the superuser
    /// half of Get Started, for someone who already keeps a corpus somewhere.
    ///
    /// Opening a different corpus invalidates everything derived from the old
    /// one, which is why the reset below is not optional: `mlxSimilarity` holds
    /// a title-embedding cache, `chatHistory` and `clusterRecommendations` are
    /// answers about notes that are no longer loaded, and a `selectedNoteID`
    /// from the old corpus resolves to nothing. Leaving any of them in place
    /// would have the window confidently describing a corpus it isn't showing.
    /// Returns whether the switch happened. Callers need that as a return value
    /// rather than inferring it from `errorMessage`, which may already be
    /// carrying something unrelated from an earlier failure.
    @discardableResult
    func switchDataFolder(to folder: URL) -> Bool {
        let url = DataLocation.eventLogURL(inFolder: folder)
        do {
            let store = try EventStore(fileURL: url)
            service = NoteService(store: store)
            dataURL = url
            UserDefaults.standard.set(folder.path, forKey: Self.dataFolderKey)
            resetCorpusScopedState()
            reload()
            statusMessage = "Now using \(folder.lastPathComponent) — \(notes.count) note\(notes.count == 1 ? "" : "s")."
            return true
        } catch {
            errorMessage = "Couldn't open a note log in \(folder.path): \(error)"
            return false
        }
    }

    /// Drops everything that describes the *previous* corpus. `janitorChat`
    /// deliberately survives: the loaded model isn't corpus-specific and costs
    /// seconds to load again.
    private func resetCorpusScopedState() {
        mlxSimilarity = nil
        similarityEngine = .tokenOverlap
        chatHistory = []
        clusterRecommendations = [:]
        janitorPreview = []
        janitorSummary = nil
        selectedNoteID = nil
        errorMessage = nil
    }

    /// Remembers that Get Started has been dealt with, so it stops opening by
    /// itself. Called when the wizard produces a prompt or a vault is chosen —
    /// not merely when the view is looked at.
    func markGetStartedComplete() {
        UserDefaults.standard.set(true, forKey: Self.getStartedDoneKey)
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
        showingGraph = false
        showingGetStarted = false
        visibleCount = 1
        statusMessage = "Showing: the single most recently updated note."
    }

    func showLast(_ n: Int) {
        showingArchived = false
        showingAssistant = false
        showingReviewQueue = false
        showingGraph = false
        showingGetStarted = false
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
        showingGraph = false
        showingGetStarted = false
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
        showingGraph = false
        showingGetStarted = false
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
        showingGraph = false
        showingGetStarted = false
        statusMessage = pending.isEmpty
            ? "Nothing is waiting on you right now."
            : "\(pending.count) item\(pending.count == 1 ? "" : "s") waiting for your OK."
    }

    func showGraph() {
        showingArchived = false
        showingAssistant = false
        showingReviewQueue = false
        showingGraph = true
        showingGetStarted = false
        statusMessage = "Note Graph View — visualizing note connections."
    }

    func selectNote(_ id: UUID?) {
        selectedNoteID = id
        if id != nil {
            showingAssistant = false
            showingReviewQueue = false
            showingGraph = false
            showingGetStarted = false
        }
    }

    /// Get Started — see `AppStore+Autopilot.swift`. Stays reachable from the
    /// sidebar forever, not just on an empty corpus: it's also how someone
    /// connects a second AI tool later, which has nothing to do with being new.
    func showGetStarted() {
        showingArchived = false
        showingAssistant = false
        showingReviewQueue = false
        showingGraph = false
        showingGetStarted = true
        statusMessage = "Get Started — connect an AI assistant to these notes."
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
