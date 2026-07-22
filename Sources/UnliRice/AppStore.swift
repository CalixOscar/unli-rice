import AppKit
import Foundation
import UnliRiceCore
import UnliRiceHost
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
    /// `ReviewQueue.cluster`. What `ReviewQueueView` renders.
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
        didSet {
            UserDefaults.standard.set(autonomyLevel, forKey: Self.autonomyKey)
            syncAgentSettings()
        }
    }

    /// The note shown in the detail pane, if any. Cleared automatically if the
    /// selected note is archived out of the default list — see `reload()`.
    @Published var selectedNoteID: UUID?

    /// Filters the note list by title, body, and tag. Lives here rather than in
    /// the view because it has to survive the list being rebuilt by `reload()`
    /// — an ingest run finishing mid-search would otherwise silently drop you
    /// back to the unfiltered list.
    ///
    /// While it's non-empty it also overrides `visibleCount`: "last 5 updated"
    /// and "notes matching 'paywall'" are different questions, and intersecting
    /// them produces the answer to neither. Searching means searching everything.
    @Published var searchText: String = ""

    /// Which archived notes are ticked for a bulk action. Only ever populated
    /// from the Archived pane — see `moveToTrash`, the one destructive path in
    /// the app, which is why the selection is deliberately not shared with the
    /// active note list.
    @Published var archiveSelection: Set<UUID> = []

    @Published var showingArchived: Bool = false
    @Published var showingReviewQueue: Bool = false
    @Published var showingGraph: Bool = false
    @Published var showingGetStarted: Bool = false
    @Published var showingRetrospective: Bool = false
    @Published var showingNotices: Bool = false

    /// Operational trust and recovery: connection evidence, verified snapshots,
    /// and in-app trash restore. Unlike notes, everything here is derived from
    /// sidecars or recovery files beside the active corpus.
    @Published var showingTrustCenter: Bool = false
    @Published var connectionActivities: [MCPConnectionActivity] = []
    @Published var vaultSnapshots: [VaultSnapshot] = []
    @Published var trashedNotes: [TrashService.TrashedNote] = []
    @Published var trustChecks: [TrustCheck] = []
    @Published var trustMessage: String?
    @Published var trustBusy: Bool = false

    /// The settings/triggers pane. Was a permanently-visible right-hand column
    /// until it became a destination like every other pane — see `AutomationView`.
    @Published var showingAutomation: Bool = false

    // MARK: - Notification centre (see AppStore+Notices.swift)

    /// Newest first. Refreshed from `NoticeStore` on every `reload()`, because
    /// `unlirice-agent` posts into the same file while this window is open —
    /// notices are the one thing here a second process writes behind our back.
    /// Written only through `refreshNotices()` — `NoticeStore` is the source of
    /// truth, and assigning here without going through it would show the user a
    /// list the agent's next post would silently overwrite.
    @Published var notices: [Notice] = []

    // MARK: - Retrospective (see AppStore+Retrospective.swift)

    /// Which period the review screen is showing. Nil means "the most recent
    /// one worth showing", resolved at display time.
    @Published var retrospectivePeriodID: String?

    // MARK: - Connect / Autopilot (see AppStore+Autopilot.swift)

    /// The house rules handed to a connected assistant — the text of the note
    /// Autopilot used to write silently.
    ///
    /// This replaced an "Autopilot" switch, and the reason generalises: the
    /// switch's entire effect was writing one note whose body was this prompt.
    /// A binary is the worst possible control for prompt text — it can only
    /// choose between someone else's wording and nothing, when the thing a
    /// person actually wants is to change a line. It was also a lie twice over:
    /// nothing persisted it, so "off" silently became "on" at the next launch,
    /// and once the note existed the switch had no effect in either position.
    ///
    /// Editable, persisted per vault, and seeded from `Autopilot.noteBody`.
    @Published var houseRulesText: String {
        didSet { scheduleHouseRulesStateSave() }
    }

    @Published var customHouseRulesPresets: [HouseRulesPreset]
    @Published var houseRulesStateError: String?

    /// Rebuilt alongside `service` whenever the active vault changes. Drafts
    /// and imported rules must follow the corpus they describe.
    var houseRulesStateStore: HouseRulesStateStore
    var houseRulesNoteID: UUID?
    var houseRulesStateSaveWorkItem: DispatchWorkItem?
    var loadingHouseRulesState = false
    /// Extra targets the user added by hand, for tools not in the catalog.
    @Published var customTargets: [MCPTarget] = []

    // MARK: - Janitor (see AppStore+Janitor.swift)

    /// What the janitor *would* do, from the last preview. Empty after a real
    /// run, since the proposals have by then become tags and queued flags.
    @Published var janitorPreview: [JanitorProposal] = []
    @Published var janitorSummary: String?
    @Published var janitorBusy: Bool = false
    @Published var similarityEngine: SimilarityEngine = .tokenOverlap

    /// Bring-your-own embeddings. Empty by default — the app ships no model and
    /// makes no network calls unless someone fills these in. `RemoteSimilarity`
    /// additionally refuses anything that isn't a loopback address.
    @Published var embeddingServerPath: String = "" {
        didSet { UserDefaults.standard.set(embeddingServerPath, forKey: Self.embeddingServerKey) }
    }
    @Published var embeddingModelName: String? {
        didSet { UserDefaults.standard.set(embeddingModelName, forKey: Self.embeddingModelKey) }
    }

    var embeddingServerURL: URL? {
        embeddingServerPath.isEmpty ? nil : URL(string: embeddingServerPath)
    }

    // MARK: - Ingest (see AppStore+Ingest.swift)

    /// What the pipelines *would* pull in, from the last preview. Cleared after
    /// a real run, the same lifecycle as `janitorPreview`.
    @Published var ingestPreview: [DiscoveredResource] = []
    @Published var ingestSummary: String?
    @Published var ingestBusy: Bool = false

    /// Folders the user has nominated for the local-document pipeline.
    ///
    /// Persisted as security-scoped bookmarks (plus display-only paths for
    /// compatibility with direct builds), and empty by default.
    @Published var scanRoots: [URL] = [] {
        didSet {
            var bookmarks = UserDefaults.standard.dictionary(forKey: "unliRice.scanRootBookmarks") as? [String: Data] ?? [:]
            let paths = Set(scanRoots.map(\.path))
            bookmarks = bookmarks.filter { paths.contains($0.key) }
            for url in scanRoots {
                if bookmarks[url.path] == nil {
                    if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        bookmarks[url.path] = bookmarkData
                    }
                }
            }
            UserDefaults.standard.set(bookmarks, forKey: "unliRice.scanRootBookmarks")
            UserDefaults.standard.set(scanRoots.map(\.path), forKey: Self.scanRootsKey)
            syncAgentSettings()
        }
    }

    @Published var claudeProjectsURL: URL? = nil {
        didSet {
            syncAgentSettings()
        }
    }

    private var dataFolderAccessStarted: Bool = false
    private var activeDataFolderURL: URL? = nil

    /// Whether the two routines may fire on their schedule. Off by default: this
    /// app reads the user's own files, and that is not something to start doing
    /// because they installed an update.
    @Published var routinesEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(routinesEnabled, forKey: Self.routinesEnabledKey)
            syncAgentSettings()
        }
    }

    /// Whether the launchd job is installed — i.e. whether any of this happens
    /// with the window closed. Read from disk rather than remembered, since the
    /// user can remove the plist by hand and a toggle claiming otherwise would
    /// be describing a job that isn't there.
    @Published var backgroundAgentInstalled: Bool = false

    /// Why the last install/uninstall failed, shown next to the toggle itself.
    @Published var backgroundAgentFailure: String?

    /// Whether advanced settings and panes are shown in the GUI.
    @Published var advancedModeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(advancedModeEnabled, forKey: Self.advancedModeKey)
        }
    }

    private static let autonomyKey = "unliRice.autonomyLevel"
    static let scanRootsKey = "unliRice.scanRoots"
    static let embeddingServerKey = "unliRice.embeddingServer"
    static let embeddingModelKey = "unliRice.embeddingModel"
    static let routinesEnabledKey = "unliRice.routinesEnabled"
    /// Pre-gallery global draft key. Read once to migrate an existing user's
    /// text into the first per-vault state file, then removed after a safe save.
    static let legacyHouseRulesKey = "unliRice.houseRulesText"
    static let advancedModeKey = "unliRice.advancedModeEnabled"
    /// Where last-run stamps *used* to live. They're in `RoutineState` beside
    /// the event log now, because `unlirice-agent` runs the same routines and a
    /// stamp only this process could see would let the same 09:00 slot be served
    /// twice. Read once, to carry an existing install across.
    static let routineLastRunKey = "unliRice.routineLastRun"
    private static let onboardingSeededKey = "unliRice.didSeedOnboardingNotes"

    /// The folder the user pointed the app at, if they ever did. In an App
    /// Store build this is display/fallback metadata only; the bookmark is the
    /// authority that grants access.
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

    /// Both are corpus-scoped and both are rebuilt by `switchDataFolder(to:)` —
    /// notices are about a corpus, and the driver's routine state lives beside
    /// its event log.
    private(set) var noticeStore: NoticeStore
    private(set) var routineDriver: RoutineDriver

    /// Every known note (active or archived) by id, refreshed on every `reload()`.
    /// Exists so the detail view can resolve a wiki-link's target — including one
    /// that's archived — without a second round trip through `NoteService`.
    private var noteIndex: [UUID: Note] = [:]

    init() {
        var url = DataLocation.eventLogURL(
            persistedFolderPath: DataLocation.isSandboxed
                ? nil
                : UserDefaults.standard.string(forKey: Self.dataFolderKey)
        )
        if let bookmarkData = UserDefaults.standard.data(forKey: "unliRice.dataFolderBookmark") {
            var isStale = false
            if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if resolvedURL.startAccessingSecurityScopedResource() {
                    dataFolderAccessStarted = true
                    activeDataFolderURL = resolvedURL
                    url = DataLocation.eventLogURL(inFolder: resolvedURL)
                    if isStale,
                       let refreshed = try? resolvedURL.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                       ) {
                        UserDefaults.standard.set(refreshed, forKey: "unliRice.dataFolderBookmark")
                    }
                }
            }
        }
        dataURL = url

        let rulesStore = HouseRulesStateStore(besideEventLog: url)
        var rulesState = HouseRulesLocalState()
        var rulesLoadError: String?
        do {
            rulesState = try rulesStore.load()
        } catch {
            rulesLoadError = error.localizedDescription
        }

        // Preserve the pre-gallery global draft on upgrade. It is claimed by
        // the vault active at first launch; later vaults start independently.
        if !rulesStore.exists,
           let legacyDraft = UserDefaults.standard.string(forKey: AppStore.legacyHouseRulesKey) {
            rulesState.draftText = legacyDraft
            do {
                try rulesStore.save(rulesState)
                UserDefaults.standard.removeObject(forKey: AppStore.legacyHouseRulesKey)
            } catch {
                rulesLoadError = "Couldn't migrate the existing House Rules draft: \(error.localizedDescription)"
            }
        }
        houseRulesStateStore = rulesStore
        houseRulesText = rulesState.draftText ?? Autopilot.noteBody
        customHouseRulesPresets = rulesState.customPresets
        houseRulesNoteID = rulesState.houseRulesNoteID
        houseRulesStateError = rulesLoadError

        autonomyLevel = UserDefaults.standard.object(forKey: AppStore.autonomyKey) as? Int ?? 1

        let scanRootBookmarks = UserDefaults.standard.dictionary(forKey: "unliRice.scanRootBookmarks") as? [String: Data] ?? [:]
        var resolvedRoots: [URL] = []
        for (_, bookmarkData) in scanRootBookmarks {
            var isStale = false
            if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                resolvedRoots.append(resolvedURL)
            }
        }
        if resolvedRoots.isEmpty && !DataLocation.isSandboxed {
            scanRoots = (UserDefaults.standard.stringArray(forKey: AppStore.scanRootsKey) ?? [])
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
        } else {
            scanRoots = resolvedRoots
        }

        if let claudeBookmark = UserDefaults.standard.data(forKey: "unliRice.claudeProjectsBookmark") {
            var isStale = false
            claudeProjectsURL = try? URL(resolvingBookmarkData: claudeBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        }

        routinesEnabled = UserDefaults.standard.bool(forKey: AppStore.routinesEnabledKey)
        advancedModeEnabled = UserDefaults.standard.bool(forKey: AppStore.advancedModeKey)
        embeddingServerPath = UserDefaults.standard.string(forKey: AppStore.embeddingServerKey) ?? ""
        embeddingModelName = UserDefaults.standard.string(forKey: AppStore.embeddingModelKey)
        do {
            let store = try EventStore(fileURL: url)
            service = NoteService(store: store)
        } catch {
            fatalError("Could not open event log at \(url.path): \(error)")
        }
        let driver = RoutineDriver(service: service, eventLogURL: url)
        routineDriver = driver
        // The driver's own store, not a second one over the same file: two
        // instances would both be correct (every mutation is under an flock) but
        // only one of them would be the one the routines post through.
        noticeStore = driver.noticeStore

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

        backgroundAgentInstalled = BackgroundAgent.isInstalled()
        migrateRoutineStampsIfNeeded()
        // Written on every launch, not only on change: this file is what the
        // background agent reads, and an install where the GUI's preferences
        // were set before the agent existed would otherwise leave it defaulted
        // to off while the window's toggle said on.
        syncAgentSettings()

        // Say what's waiting before the user goes looking. This is the whole
        // "don't make a special trip" idea — the review queue and a finished
        // month both surface as notices rather than as a chore you'd have to
        // remember to check.
        routineDriver.announceNow(settings: agentSettings)
        refreshNotices()
    }

    /// Whether anything in this corpus was written by a person or an agent, as
    /// opposed to arriving from `Onboarding.seedIfNeeded`.
    var hasUserAuthoredNotes: Bool {
        (notes + archivedNotes).contains { !$0.sources.isSubset(of: [Onboarding.source]) }
    }

    /// Whether the app is reading its default location rather than a folder the
    /// user nominated. Drives the "Use the default location" affordance, which
    /// exists because this preference used to be one-way: it could be set from
    /// the UI and never cleared, so a wrong folder was unrecoverable without
    /// editing defaults by hand.
    var usingDefaultDataFolder: Bool {
        (UserDefaults.standard.string(forKey: Self.dataFolderKey) ?? "").isEmpty
    }

    /// Points the app back at its shared App Group container.
    func useDefaultDataFolder() {
        UserDefaults.standard.removeObject(forKey: Self.dataFolderKey)
        UserDefaults.standard.removeObject(forKey: "unliRice.dataFolderBookmark")
        _ = switchDataFolder(
            to: DataLocation.defaultEventLogURL().deletingLastPathComponent(),
            persist: false
        )
    }

    /// - Parameter persist: whether to remember this folder for next launch.
    ///   False only for `useDefaultDataFolder`, which wants the preference
    ///   *absent* rather than set to the default path.
    @discardableResult
    func switchDataFolder(to folder: URL, persist: Bool = true) -> Bool {
        flushHouseRulesState()
        if dataFolderAccessStarted {
            activeDataFolderURL?.stopAccessingSecurityScopedResource()
            dataFolderAccessStarted = false
            activeDataFolderURL = nil
        }

        let isScoped = folder.startAccessingSecurityScopedResource()
        let url = DataLocation.eventLogURL(inFolder: folder)
        do {
            let nextRulesStore = HouseRulesStateStore(besideEventLog: url)
            let nextRulesState: HouseRulesLocalState
            var nextRulesError: String?
            do {
                nextRulesState = try nextRulesStore.load()
            } catch {
                nextRulesState = HouseRulesLocalState()
                nextRulesError = error.localizedDescription
            }

            let store = try EventStore(fileURL: url)
            service = NoteService(store: store)
            dataURL = url
            dataFolderAccessStarted = isScoped
            activeDataFolderURL = isScoped ? folder : nil
            let driver = RoutineDriver(service: service, eventLogURL: url)
            routineDriver = driver
            noticeStore = driver.noticeStore

            loadingHouseRulesState = true
            houseRulesStateStore = nextRulesStore
            houseRulesText = nextRulesState.draftText ?? Autopilot.noteBody
            customHouseRulesPresets = nextRulesState.customPresets
            houseRulesNoteID = nextRulesState.houseRulesNoteID
            houseRulesStateError = nextRulesError
            loadingHouseRulesState = false
            if persist {
                UserDefaults.standard.set(folder.path, forKey: Self.dataFolderKey)
                if let bookmarkData = try? folder.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(bookmarkData, forKey: "unliRice.dataFolderBookmark")
                }
            }
            syncAgentSettings()
            resetCorpusScopedState()
            // Also clears the search box and any "last 5" narrowing. A filter
            // carried across a corpus switch describes the corpus you just
            // left, and an empty result would read as "the folder is empty".
            searchText = ""
            visibleCount = max(visibleCount, 5)
            reload()
            statusMessage = notes.isEmpty
                ? "Now using \(folder.lastPathComponent) — it's empty. Your other notes are still where you left them."
                : "Now using \(folder.lastPathComponent) — \(notes.count) note\(notes.count == 1 ? "" : "s")."
            return true
        } catch {
            errorMessage = "Couldn't open a note log in \(folder.path): \(error)"
            if isScoped {
                folder.stopAccessingSecurityScopedResource()
            }
            return false
        }
    }

    /// Drops everything that describes the *previous* corpus.
    private func resetCorpusScopedState() {
        janitorPreview = []
        janitorSummary = nil
        selectedNoteID = nil
        errorMessage = nil
        // News about the corpus we just stopped looking at, and a review screen
        // describing a period of it.
        notices = []
        connectionActivities = []
        vaultSnapshots = []
        trashedNotes = []
        trustChecks = []
        trustMessage = nil
        retrospectivePeriodID = nil
        showingRetrospective = false
        showingNotices = false
        showingTrustCenter = false
    }

    /// Everything the background agent needs, as the GUI currently has it.
    var agentSettings: AgentSettings {
        let scanBookmarks = UserDefaults.standard.dictionary(forKey: "unliRice.scanRootBookmarks") as? [String: Data] ?? [:]
        let dataBookmark = UserDefaults.standard.data(forKey: "unliRice.dataFolderBookmark")
        let claudeBookmark = UserDefaults.standard.data(forKey: "unliRice.claudeProjectsBookmark")

        return AgentSettings(
            routinesEnabled: routinesEnabled,
            autonomyLevel: autonomyLevel,
            dataFolderPath: UserDefaults.standard.string(forKey: Self.dataFolderKey),
            scanRootPaths: scanRoots.map(\.path),
            // Monthly retrospectives are part of the product rather than a
            // hidden preference: the old key had no UI and was always true.
            monthlyReviewEnabled: true,
            scanRootBookmarks: scanBookmarks,
            dataFolderBookmark: dataBookmark,
            claudeProjectsBookmark: claudeBookmark
        )
    }

    /// Mirrors the GUI's preferences into the file `unlirice-agent` reads.
    ///
    /// The GUI is the only writer, and the agent only reads — an agent that
    /// could change what it's allowed to do would be a different kind of
    /// component than this one is. See `AgentSettings` for why it isn't
    /// `UserDefaults`.
    func syncAgentSettings() {
        do {
            try agentSettings.save()
        } catch {
            errorMessage = "Couldn't save background settings: \(error)"
        }
    }

    /// Carries pre-daemon last-run stamps out of `UserDefaults` and into the
    /// corpus-scoped state file, once.
    ///
    /// Without this, installing the agent would make every routine look
    /// unserved, so the first tick after upgrading would run an unexpected
    /// ingest. Not a data risk — `IngestRunner` skips what it already indexed —
    /// but a surprise, and a surprise from a component whose entire job is to be
    /// unsurprising.
    private func migrateRoutineStampsIfNeeded() {
        let stateURL = RoutineState.url(besideEventLog: dataURL)
        guard !FileManager.default.fileExists(atPath: stateURL.path),
              let stamps = UserDefaults.standard.dictionary(forKey: Self.routineLastRunKey) as? [String: Double],
              !stamps.isEmpty
        else { return }

        var state = RoutineState()
        for (key, seconds) in stamps {
            state.lastRuns[key] = Date(timeIntervalSince1970: seconds)
        }
        try? state.save(to: stateURL)
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
            refreshNotices()
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
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty else { return source.filter { $0.matches(query) } }
        return visibleCount == 0 ? [] : Array(source.prefix(visibleCount))
    }

    /// True when the list is showing fewer notes than exist and the user hasn't
    /// asked it to. Drives the "showing N of M" affordance — with a scrolling
    /// list there's no longer any visual cue that the list was truncated at all,
    /// which is precisely the bug that made 144 ingested notes look like 5.
    var hiddenNoteCount: Int {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let total = showingArchived ? archivedNotes.count : notes.count
        return max(0, total - visibleNotes.count)
    }

    func showEverything() {
        showLast(Int.max)
    }

    /// Turns every main-column pane off, so a `show…` method only has to turn
    /// its own on.
    ///
    /// Each of these methods used to list the others by hand, which worked
    /// exactly until a new pane was added — the review screen and the
    /// notification centre would each have needed a line in six places, and the
    /// one that got missed would show through underneath another view.
    func closeAllPanes() {
        showingArchived = false
        showingReviewQueue = false
        showingGraph = false
        showingGetStarted = false
        showingRetrospective = false
        showingNotices = false
        showingTrustCenter = false
        showingAutomation = false
    }

    func showLatest() {
        closeAllPanes()
        visibleCount = 1
        statusMessage = "Showing: the single most recently updated note."
    }

    /// `n` is a ceiling, not a promise — "Everything" passes `Int.max`, and
    /// `showAllNotes` re-passes whatever the last ceiling was. The message has
    /// to describe what's on screen rather than echo the number, or asking for
    /// everything and then clicking All Notes reports "last
    /// 9223372036854775807 updated notes".
    func showLast(_ n: Int) {
        closeAllPanes()
        visibleCount = n
        let total = notes.count
        statusMessage = n >= total
            ? "Showing every note."
            : "Showing: last \(n) updated notes."
    }

    func showAllNotes() {
        showLast(visibleCount == 0 ? 5 : visibleCount)
    }

    func showArchived() {
        closeAllPanes()
        showingArchived = true
        archiveSelection = []
        // No cap: the list scrolls now, and a hidden 51st archived note is one
        // the user can neither restore nor trash.
        visibleCount = Int.max
        statusMessage = archivedNotes.isEmpty
            ? "No archived notes."
            : "Showing \(archivedNotes.count) archived note\(archivedNotes.count == 1 ? "" : "s")."
    }

    /// The review queue, full width in the main column — not the narrow
    /// right-hand panel it used to live in. A pile of near-duplicate notes
    /// needs room for full titles and an actual "Keep this one" button per
    /// note; 260pt of sidebar was cramping both into truncated text.
    func showReviewQueue() {
        closeAllPanes()
        showingReviewQueue = true
        statusMessage = pending.isEmpty
            ? "Nothing is waiting on you right now."
            : "\(pending.count) item\(pending.count == 1 ? "" : "s") waiting for your OK."
    }

    func showAutomation() {
        closeAllPanes()
        showingAutomation = true
        statusMessage = "Automation — what runs on its own, and what only runs when you ask."
    }

    func showTrustCenter() {
        closeAllPanes()
        showingTrustCenter = true
        refreshTrustCenter()
        statusMessage = "Trust Center — connection evidence, recovery points, and note history."
    }

    func showGraph() {
        closeAllPanes()
        showingGraph = true
        statusMessage = "Note Graph View — visualizing note connections."
    }

    func selectNote(_ id: UUID?) {
        selectedNoteID = id
        if id != nil {
            // Not `closeAllPanes()`: `showingArchived` deliberately survives
            // opening a note, so closing it returns you to the archived list you
            // were reading rather than to All Notes.
            showingReviewQueue = false
            showingGraph = false
            showingGetStarted = false
            showingRetrospective = false
            showingNotices = false
            showingTrustCenter = false
            showingAutomation = false
        }
    }

    /// Get Started — see `AppStore+Autopilot.swift`. Stays reachable from the
    /// sidebar forever, not just on an empty corpus: it's also how someone
    /// connects a second AI tool later, which has nothing to do with being new.
    func showGetStarted() {
        closeAllPanes()
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

    deinit {
        if dataFolderAccessStarted {
            activeDataFolderURL?.stopAccessingSecurityScopedResource()
        }
    }
}
