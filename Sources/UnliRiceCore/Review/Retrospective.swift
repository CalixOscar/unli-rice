import Foundation

/// A stretch of time to look back on.
///
/// Only months and years, because those are the two units a person actually
/// thinks in when asking "what was I doing then". A week is too short to have
/// forgotten and a quarter is a unit of work, not of memory.
public struct RetrospectivePeriod: Equatable, Sendable, Identifiable, Hashable {
    public enum Span: String, Sendable, Codable {
        case month
        case year
    }

    public let span: Span
    /// Inclusive.
    public let start: Date
    /// Exclusive — the first instant *after* the period.
    public let end: Date

    public init(span: Span, start: Date, end: Date) {
        self.span = span
        self.start = start
        self.end = end
    }

    /// `2026-06` for a month, `2026` for a year. Stable, sortable, and what a
    /// `NoticeDestination.retrospective` carries.
    public var id: String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents(in: .current, from: start)
        let year = parts.year ?? 0
        switch span {
        case .year: return String(format: "%04d", year)
        case .month: return String(format: "%04d-%02d", year, parts.month ?? 0)
        }
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    public func displayName(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = span == .year ? "yyyy" : "LLLL yyyy"
        return formatter.string(from: start)
    }

    /// The month `date` falls in.
    public static func month(containing date: Date, calendar: Calendar = .current) -> RetrospectivePeriod? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        return RetrospectivePeriod(span: .month, start: interval.start, end: interval.end)
    }

    public static func year(containing date: Date, calendar: Calendar = .current) -> RetrospectivePeriod? {
        guard let interval = calendar.dateInterval(of: .year, for: date) else { return nil }
        return RetrospectivePeriod(span: .year, start: interval.start, end: interval.end)
    }

    /// The month before the one `date` is in — what a "your month is ready"
    /// notice points at, since the current month isn't over yet.
    public static func previousMonth(before date: Date, calendar: Calendar = .current) -> RetrospectivePeriod? {
        guard let earlier = calendar.date(byAdding: .month, value: -1, to: date) else { return nil }
        return month(containing: earlier, calendar: calendar)
    }
}

/// A count with a name, ordered by count. Used for both projects and tags.
public struct RetrospectiveTally: Equatable, Sendable, Identifiable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

/// Who did the writing.
///
/// The corpus is written by several agents at once — that is the whole premise
/// of the MCP server — and until now the screen showed *what* was written
/// without ever saying by whom. Every event already carries a `source`; this is
/// that field, counted.
public struct ContributorTally: Equatable, Sendable, Identifiable {
    /// The raw `source` string off the event log (`claude`, `codex`, `human`…).
    public let identity: String
    /// The same thing, as a person would say it.
    public let name: String
    /// Notes this contributor *started* in the period.
    public let notesCreated: Int
    /// Notes it added to, tagged, or filed that someone else started — the
    /// collaboration the source set records and a creator count would miss.
    public let notesTouched: Int
    /// Words written into notes it created. A count of notes flatters whoever
    /// writes the most stubs; this is the second half of that picture.
    public let wordsWritten: Int

    public var id: String { identity }

    public init(identity: String, name: String, notesCreated: Int, notesTouched: Int, wordsWritten: Int) {
        self.identity = identity
        self.name = name
        self.notesCreated = notesCreated
        self.notesTouched = notesTouched
        self.wordsWritten = wordsWritten
    }
}

/// One month's worth of activity inside a year digest — the "oh right, that's
/// what February was" row.
public struct MonthlyActivity: Equatable, Sendable, Identifiable {
    public let period: RetrospectivePeriod
    public let noteCount: Int
    /// The project that dominated that month, if any one did.
    public let leadingProject: String?
    /// A note from that month worth being reminded of.
    public let highlight: Note?

    public var id: String { period.id }

    public init(period: RetrospectivePeriod, noteCount: Int, leadingProject: String?, highlight: Note?) {
        self.period = period
        self.noteCount = noteCount
        self.leadingProject = leadingProject
        self.highlight = highlight
    }
}

/// What a period looked like.
public struct RetrospectiveDigest: Equatable, Sendable {
    public let period: RetrospectivePeriod
    /// Notes *created* in the period.
    public let notesCreated: Int
    /// Notes that existed before and were added to during it — the ones that
    /// were being worked on rather than started.
    public let notesRevisited: Int
    public let projects: [RetrospectiveTally]
    public let tags: [RetrospectiveTally]
    /// Every agent (and person) that wrote something in the period, busiest
    /// first.
    public let contributors: [ContributorTally]
    /// Populated for a year; empty for a month.
    public let months: [MonthlyActivity]
    public let highlights: [Note]
    public let busiestMonth: MonthlyActivity?

    public var isEmpty: Bool { notesCreated == 0 && notesRevisited == 0 }

    public init(
        period: RetrospectivePeriod,
        notesCreated: Int,
        notesRevisited: Int,
        projects: [RetrospectiveTally],
        tags: [RetrospectiveTally],
        contributors: [ContributorTally],
        months: [MonthlyActivity],
        highlights: [Note],
        busiestMonth: MonthlyActivity?
    ) {
        self.period = period
        self.notesCreated = notesCreated
        self.notesRevisited = notesRevisited
        self.projects = projects
        self.tags = tags
        self.contributors = contributors
        self.months = months
        self.highlights = highlights
        self.busiestMonth = busiestMonth
    }
}

/// Reading the corpus back to the person who made it.
///
/// **This needs no new data, and that is the whole reason it exists.** Every
/// note already carries when it happened (`createdAt`/`updatedAt`), what it came
/// from (`sources`, and the ingest pipelines' `**Project:**` line), and what it
/// was about (tags, `[[links]]`, backlinks). Nothing here writes, schedules, or
/// asks anything of the user — it is a pure function over notes, in the same
/// shape and for the same reason as `Janitor.scan`.
public enum Retrospective {
    /// Every period the corpus has something to say about, newest first: the
    /// months that contain notes, and the years that contain those months.
    ///
    /// Derived rather than enumerated so the list can't offer an empty January
    /// on a corpus that started in March — an empty retrospective is a worse
    /// answer than not offering one.
    public static func availablePeriods(notes: [Note], calendar: Calendar = .current) -> [RetrospectivePeriod] {
        var months: Set<RetrospectivePeriod> = []
        var years: Set<RetrospectivePeriod> = []
        for note in notes {
            if let month = RetrospectivePeriod.month(containing: note.createdAt, calendar: calendar) {
                months.insert(month)
            }
            if let year = RetrospectivePeriod.year(containing: note.createdAt, calendar: calendar) {
                years.insert(year)
            }
        }
        // Grouped by year, newest year first, each year heading the months
        // inside it — the order a picker reads in. Sorting purely by start date
        // would bury "2026" below every month of 2026, since January 1st is the
        // earliest date in the year it names.
        return (years.union(months)).sorted { lhs, rhs in
            let left = calendar.component(.year, from: lhs.start)
            let right = calendar.component(.year, from: rhs.start)
            if left != right { return left > right }
            if lhs.span != rhs.span { return lhs.span == .year }
            return lhs.start > rhs.start
        }
    }

    public static func digest(
        for period: RetrospectivePeriod,
        notes: [Note],
        calendar: Calendar = .current
    ) -> RetrospectiveDigest {
        let created = notes.filter { period.contains($0.createdAt) }
        let revisited = notes.filter { !period.contains($0.createdAt) && period.contains($0.updatedAt) }

        let months: [MonthlyActivity] = period.span == .year
            ? monthlyBreakdown(of: period, notes: created, calendar: calendar)
            : []

        return RetrospectiveDigest(
            period: period,
            notesCreated: created.count,
            notesRevisited: revisited.count,
            projects: tally(created.compactMap(project(of:))),
            tags: tally(created.flatMap { $0.tags }),
            // Revisits count too: a period in which another agent spent its
            // time improving notes it didn't write is a period that agent
            // worked in, and leaving it off the list would say otherwise.
            contributors: contributors(created: created, revisited: revisited),
            months: months,
            highlights: highlights(among: created, limit: period.span == .year ? 8 : 5),
            busiestMonth: months.max { $0.noteCount < $1.noteCount }.flatMap { $0.noteCount > 0 ? $0 : nil }
        )
    }

    /// The project a note belongs to, if anything in it says so.
    ///
    /// Read from the `**Project:** \`/some/path\`` line the ingest pipelines
    /// write, reduced to the folder's own name — the full path is what makes the
    /// note precise and the last component is what makes a list of them
    /// readable. Notes written by hand have no project and are counted under
    /// none rather than guessed at.
    public static func project(of note: Note) -> String? {
        guard let range = note.body.range(of: "**Project:**") else { return nil }
        let rest = note.body[range.upperBound...]
        let line = rest.prefix { !$0.isNewline }
        let cleaned = line
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Must be an absolute path. Anything else is prose that happened to
        // start with the same words — a real run over the corpus turned up
        // "Architecturally" as a top project that way, which is the sort of
        // nonsense that makes a whole screen untrustworthy.
        guard cleaned.hasPrefix("/") else { return nil }

        let components = cleaned
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        // `/Users/someone` is a home directory, not a project. Same first real
        // run: the home folder's name came out as the single most-worked
        // "project", which is true only in the least useful possible sense.
        guard components.count > 2 else { return nil }
        return components.last
    }

    /// Who a note's `source` string really represents.
    ///
    /// Most sources are already the answer — `claude`, `codex`, `gemini` are
    /// typed by the agent itself when it calls the MCP server. `ingest` is not:
    /// every pipeline writes under that one identity, so a corpus half-built by
    /// the Claude Code session importer and half by the Obsidian one would
    /// report a single anonymous "ingest" as its biggest contributor. The
    /// pipeline stamps its own `identifier` on the note as a tag, so that is
    /// what gets credited.
    public static func contributorIdentity(of source: String, in note: Note) -> String {
        guard source == IngestRunner.sourceIdentity else { return source }
        // Ordered, not `first(where:)` over the set — tag sets are unordered and
        // a note carrying two pipeline tags must not change contributor between
        // two viewings of the same month.
        for pipeline in ingestPipelines where note.tags.contains(pipeline) {
            return "\(IngestRunner.sourceIdentity):\(pipeline)"
        }
        return source
    }

    /// Known identities spelled the way their makers spell them, and anything
    /// else title-cased rather than dropped — a new agent should show up under
    /// its own name the first time it writes, without a code change here.
    public static func contributorName(of identity: String) -> String {
        if let known = knownContributorNames[identity] { return known }
        return identity
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == ":" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static let ingestPipelines = ["claude-session", "obsidian-import", "document"]

    private static let knownContributorNames: [String: String] = [
        "human": "You",
        "claude": "Claude",
        "codex": "Codex",
        "chatgpt": "ChatGPT",
        "gemini": "Gemini",
        "kimi": "Kimi",
        "cursor": "Cursor",
        "antigravity": "Antigravity",
        JanitorRunner.sourceIdentity: "Janitor (on-device)",
        Onboarding.source: "Unli Rice",
        IngestRunner.sourceIdentity: "Imported",
        "\(IngestRunner.sourceIdentity):claude-session": "Claude Code sessions",
        "\(IngestRunner.sourceIdentity):obsidian-import": "Obsidian vault",
        "\(IngestRunner.sourceIdentity):document": "Local documents"
    ]

    private static func contributors(created: [Note], revisited: [Note]) -> [ContributorTally] {
        var notesCreated: [String: Int] = [:]
        var notesTouched: [String: Int] = [:]
        var wordsWritten: [String: Int] = [:]

        for note in created {
            let author = contributorIdentity(of: note.creator, in: note)
            notesCreated[author, default: 0] += 1
            wordsWritten[author, default: 0] += note.body.split(whereSeparator: \.isWhitespace).count
            for editor in note.editors {
                notesTouched[contributorIdentity(of: editor, in: note), default: 0] += 1
            }
        }
        for note in revisited {
            for editor in note.editors {
                notesTouched[contributorIdentity(of: editor, in: note), default: 0] += 1
            }
        }

        return Set(notesCreated.keys).union(notesTouched.keys)
            .map { identity in
                ContributorTally(
                    identity: identity,
                    name: contributorName(of: identity),
                    notesCreated: notesCreated[identity] ?? 0,
                    notesTouched: notesTouched[identity] ?? 0,
                    wordsWritten: wordsWritten[identity] ?? 0
                )
            }
            // Authorship first: an agent that wrote ten notes ranks above one
            // that tagged a hundred. Name breaks ties so a redraw can't reorder.
            .sorted {
                ($0.notesCreated, $0.notesTouched, $1.name) > ($1.notesCreated, $1.notesTouched, $0.name)
            }
    }

    // MARK: - Private

    private static func tally(_ names: [String]) -> [RetrospectiveTally] {
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        return counts
            .map { RetrospectiveTally(name: $0.key, count: $0.value) }
            // Count first, then name — so a redraw can't reorder a tie and make
            // the same month look different on a second viewing.
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    private static func monthlyBreakdown(
        of year: RetrospectivePeriod,
        notes: [Note],
        calendar: Calendar
    ) -> [MonthlyActivity] {
        var cursor = year.start
        var result: [MonthlyActivity] = []
        while cursor < year.end, let month = RetrospectivePeriod.month(containing: cursor, calendar: calendar) {
            let inMonth = notes.filter { month.contains($0.createdAt) }
            result.append(
                MonthlyActivity(
                    period: month,
                    noteCount: inMonth.count,
                    leadingProject: tally(inMonth.compactMap(project(of:))).first?.name,
                    highlight: highlights(among: inMonth, limit: 1).first
                )
            )
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// The notes most likely to produce recognition rather than a shrug.
    ///
    /// Ranked, in order of weight: how many other notes point at it (a note the
    /// corpus keeps referring back to is one that mattered), whether a person
    /// rather than a pipeline wrote it, and how much was written. Archived notes
    /// are excluded — archiving is how someone says stop showing me this, and a
    /// year-in-review that resurfaces exactly what you filed away would be the
    /// app arguing with its user, the same mistake `JanitorRunner` checks the
    /// untag history to avoid.
    public static func highlights(among notes: [Note], limit: Int) -> [Note] {
        notes
            .filter { !$0.archived && !$0.sources.isSubset(of: [Onboarding.source]) }
            .sorted { lhs, rhs in
                let left = (score(lhs), lhs.createdAt.timeIntervalSince1970)
                let right = (score(rhs), rhs.createdAt.timeIntervalSince1970)
                return left > right
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func score(_ note: Note) -> Int {
        var score = note.backlinks.count * 10
        score += note.outboundLinks.count * 3
        let machineSources: Set<String> = [
            IngestRunner.sourceIdentity, Onboarding.source, JanitorRunner.sourceIdentity
        ]
        if !note.sources.isSubset(of: machineSources) { score += 8 }
        score += min(note.body.count / 200, 6)
        score += min(note.tags.count, 4)
        return score
    }
}
