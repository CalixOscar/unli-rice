import Foundation

/// The pipelines that are active for a given set of nominated folders.
///
/// One definition, used by the GUI's panel and by `unlirice-agent`. They used to
/// be assembled in `AppStore`, which was fine while the window was the only
/// thing that could run them; with a daemon in the picture, two lists that
/// drifted apart would mean the scheduled run did something different from the
/// button, which is the sort of difference nobody notices until it matters.
public enum Pipelines {
    private static func isSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// `LocalFileImporter` is omitted entirely when no folder has been
    /// nominated, rather than included and returning nothing: there is no
    /// default root by design, and a pipeline listed as active while scanning
    /// nowhere is a lie the UI would be telling.
    public static func standard(scanRoots: [URL], claudeProjectsDirectory: URL? = nil) -> [ResourceImporter] {
        var pipelines: [ResourceImporter] = []

        let claudeDir = claudeProjectsDirectory ?? (isSandboxed() ? nil : ClaudeSessionImporter.defaultProjectsDirectory())
        if let claudeDir = claudeDir {
            pipelines.append(ClaudeSessionImporter(projectsDirectory: claudeDir))
        }

        if !scanRoots.isEmpty {
            pipelines.append(LocalFileImporter(
                roots: scanRoots,
                maximumDepth: 20,
                maximumFilesPerRoot: 10000,
                minimumBytes: 0
            ))
        }
        return pipelines
    }
}

/// What one tick did.
public struct RoutineTickReport: Equatable, Sendable {
    public struct Ran: Equatable, Sendable {
        public let kind: RoutineKind
        public let summary: String
        public let failed: Bool
    }

    /// Empty when nothing was due, or when another process held the lock.
    public var ran: [Ran] = []
    /// Notices posted this tick, in the order they were posted.
    public var posted: [Notice] = []
    /// Why nothing ran, when nothing did — surfaced so a routine that keeps
    /// declining never looks the same as one that's broken.
    public var holds: [RoutineKind: String] = [:]

    public var didWork: Bool { !ran.isEmpty }
}

/// Runs the routines: the single place that turns "the scheduler says yes" into
/// work actually happening.
///
/// **Both the GUI heartbeat and `unlirice-agent` call this**, which is the whole
/// point. Before it existed, "run the routines" lived inside `AppStore`, so
/// closing the window stopped the automation — the app asked to be trusted with
/// unattended maintenance and then only did it while being watched.
///
/// It deliberately does not decide anything about permissions. `IngestRunner`
/// and `JanitorRunner` still own their own boundaries — the janitor can still
/// only produce `{tagged, flagged}` and ingest only `{created, appended,
/// tagged}` — and running from a daemon rather than a button grants neither of
/// them anything extra. That property is enforced in those two types, not here,
/// which is exactly why this file can be as simple as it is.
public final class RoutineDriver {
    private let service: NoteService
    private let rawStore: RawStore
    private let notices: NoticeStore
    private let stateURL: URL
    private let eventLogURL: URL
    private let pipelines: (AgentSettings) -> [ResourceImporter]

    /// `pipelines` is injectable for one reason: the default one scans
    /// `~/.claude/projects`, so a test that used it would ingest the machine's
    /// real conversation history into its temporary corpus. Production has no
    /// reason to pass anything.
    public init(
        service: NoteService,
        eventLogURL: URL,
        pipelines: @escaping (AgentSettings) -> [ResourceImporter] = { Pipelines.standard(scanRoots: $0.scanRoots, claudeProjectsDirectory: $0.claudeProjectsURL) }
    ) {
        self.service = service
        self.eventLogURL = eventLogURL
        self.pipelines = pipelines
        self.rawStore = RawStore(directoryURL: RawStore.directoryURL(besideEventLog: eventLogURL))
        self.notices = NoticeStore(besideEventLog: eventLogURL)
        self.stateURL = RoutineState.url(besideEventLog: eventLogURL)
    }

    public var noticeStore: NoticeStore { notices }

    /// One heartbeat: run whatever is due, then say whatever is worth saying.
    ///
    /// Safe to call as often as you like. It is called from a coarse 5-minute
    /// timer rather than a precise alarm because `RoutineSchedule.lastFiring`
    /// asks "has this slot passed unserved", not "is it exactly 09:00" — which
    /// is what lets a slot survive the Mac being asleep at the scheduled minute.
    @discardableResult
    public func tick(
        now: Date = Date(),
        settings: AgentSettings,
        machine: MachineState,
        similarity: SimilarityProvider = TokenOverlapSimilarity(),
        calendar: Calendar = .current
    ) -> RoutineTickReport {
        var report = RoutineTickReport()

        // Whoever else is mid-tick wins; this one is served by the next beat.
        // The GUI's timer and launchd's interval genuinely do land together.
        guard let lock = RoutineRunLock(besideEventLog: eventLogURL) else { return report }
        // The lock is held by this object's lifetime, and nothing below reads
        // it — without this, ARC is free to release it before the work is done.
        defer { withExtendedLifetime(lock) {} }

        var state = RoutineState.load(from: stateURL)

        // Automatically ingest inbox notes and regenerate export mirror if Unli Rice export folder exists
        let exportURL = settings.exportFolderURL ?? {
            let defaultPath = NSString(string: "~/Documents/Unli Rice").expandingTildeInPath
            let url = URL(fileURLWithPath: defaultPath, isDirectory: true)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        if let exportURL = exportURL {
            let isScoped = exportURL.startAccessingSecurityScopedResource()
            let inboxURL = exportURL.appendingPathComponent("Notes for Unli Rice", isDirectory: true)
            if FileManager.default.fileExists(atPath: inboxURL.path) {
                let inboxImporter = LocalFileImporter(
                    roots: [inboxURL],
                    maximumDepth: 5,
                    maximumFilesPerRoot: 1000,
                    minimumBytes: 0
                )
                let runner = IngestRunner(service: service, rawStore: rawStore)
                _ = try? runner.run(importer: inboxImporter)
            }

            try? MirrorExporter.exportMirror(
                profileName: "Unli Rice",
                vaultFolderURL: eventLogURL.deletingLastPathComponent(),
                noteService: service,
                customExportDirectory: exportURL
            )
            if isScoped { exportURL.stopAccessingSecurityScopedResource() }
        }

        if settings.routinesEnabled {
            if let claudeURL = settings.claudeProjectsURL {
                let isScoped = claudeURL.startAccessingSecurityScopedResource()
                let claudeImporter = ClaudeSessionImporter(projectsDirectory: claudeURL, minimumMessages: 4)
                let runner = IngestRunner(service: service, rawStore: rawStore)
                _ = try? runner.run(importer: claudeImporter, config: IngestConfig(noteBudget: 40))
                if isScoped { claudeURL.stopAccessingSecurityScopedResource() }
            }

            for kind in RoutineKind.allCases {
                let decision = RoutineScheduler.decide(
                    schedule: .recommended(for: kind),
                    now: now,
                    lastRun: state.lastRun(of: kind),
                    machine: machine,
                    autonomy: settings.autonomy,
                    calendar: calendar
                )
                guard decision.shouldRun else {
                    if case .hold(let reason) = decision { report.holds[kind] = reason }
                    continue
                }

                do {
                    let result = try run(kind, settings: settings, similarity: similarity)
                    report.ran.append(.init(kind: kind, summary: result.summary, failed: false))
                    // A run that touched nothing is the system working. Saying
                    // so is how a notification centre earns being ignored.
                    if result.changedSomething {
                        report.posted.append(
                            notices.post(
                                NoticeFactory.routineRan(kind: kind, summary: result.summary, at: now)
                            )
                        )
                    }
                    // Stamped only after the work actually finished, so a crash
                    // mid-run leaves the slot unserved and the next tick retries.
                    state.recordRun(of: kind, at: now)
                } catch {
                    report.ran.append(.init(kind: kind, summary: "\(error)", failed: true))
                    report.posted.append(
                        notices.post(NoticeFactory.routineFailed(kind: kind, reason: "\(error)", at: now))
                    )
                    // Deliberately *not* stamped: a failed slot stays unserved.
                }
            }
        }

        report.posted.append(contentsOf: announce(now: now, settings: settings, state: &state, calendar: calendar))
        try? state.save(to: stateURL)
        return report
    }

    /// Posts the "waiting on you" and "your month is ready" notices, without
    /// running anything.
    ///
    /// Split out so the GUI can call it after a *manual* janitor run and at
    /// launch: the review queue filling up is worth mentioning however it got
    /// full, and someone who never turns routines on should still get their
    /// month back.
    public func announce(
        now: Date = Date(),
        settings: AgentSettings,
        state: inout RoutineState,
        calendar: Calendar = .current
    ) -> [Notice] {
        var posted: [Notice] = []
        let notes = (try? service.listNotes(includeArchived: false)) ?? []

        if let pending = try? service.pendingReviews(), !pending.isEmpty {
            let clusters = ReviewQueue.cluster(
                pending.map { ReviewItem(note: $0.note, flag: $0.flag) },
                resolveNote: { id in notes.first { $0.id == id } }
            )
            if let notice = NoticeFactory.reviewQueue(pendingCount: pending.count, clusterCount: clusters.count) {
                posted.append(notices.post(notice))
            }
        }

        if settings.monthlyReviewEnabled,
           let period = DigestAnnouncer.pendingAnnouncement(
               now: now, lastAnnouncedPeriodID: state.lastDigestPeriod, notes: notes, calendar: calendar
           ) {
            let digest = Retrospective.digest(for: period, notes: notes, calendar: calendar)
            posted.append(
                notices.post(
                    NoticeFactory.retrospective(period, noteCount: digest.notesCreated, calendar: calendar)
                )
            )
            state.lastDigestPeriod = period.id
        }

        return posted
    }

    /// `announce` against the persisted state, for callers that don't hold it.
    @discardableResult
    public func announceNow(
        now: Date = Date(),
        settings: AgentSettings,
        calendar: Calendar = .current
    ) -> [Notice] {
        var state = RoutineState.load(from: stateURL)
        let posted = announce(now: now, settings: settings, state: &state, calendar: calendar)
        try? state.save(to: stateURL)
        return posted
    }

    // MARK: - Private

    private struct RunResult {
        let summary: String
        /// Read from the runners' own counts rather than sniffed out of their
        /// summary text — a "285 sessions scanned, 0 new" line is full of
        /// digits and describes nothing having happened.
        let changedSomething: Bool
    }

    private func run(
        _ kind: RoutineKind,
        settings: AgentSettings,
        similarity: SimilarityProvider
    ) throws -> RunResult {
        switch kind {
        case .dataIngestion:
            let runner = IngestRunner(service: service, rawStore: rawStore)
            var summaries: [String] = []
            var changed = 0
            for importer in pipelines(settings) {
                let report = try runner.run(importer: importer)
                summaries.append(report.summary)
                changed += report.indexed.count + report.revised.count
            }
            return RunResult(summary: summaries.joined(separator: " · "), changedSomething: changed > 0)

        case .systemImprovement:
            let runner = JanitorRunner(service: service, similarity: similarity)
            let report = try runner.run(config: JanitorConfig(autonomy: settings.autonomy))
            return RunResult(
                summary: report.summary,
                changedSomething: report.applied.count + report.queued.count > 0
            )
        }
    }
}
