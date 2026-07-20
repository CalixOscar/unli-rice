import Foundation

public enum IngestOutcome: Sendable, Equatable {
    /// A resource that had no note before this run.
    case indexed
    /// A resource whose file has changed since it was last seen; the note gained
    /// a revision entry and `/raw` gained the new bytes. The old copy is kept.
    case revised
    /// Deliberately not acted on. `reason` says why, for the run report.
    case skipped(reason: String)
}

public struct IngestRunReport: Sendable {
    public let importer: String
    public let results: [(resource: DiscoveredResource, outcome: IngestOutcome)]

    public var indexed: [DiscoveredResource] { results.filter { $0.outcome == .indexed }.map(\.resource) }
    public var revised: [DiscoveredResource] { results.filter { $0.outcome == .revised }.map(\.resource) }
    public var skipped: [(resource: DiscoveredResource, reason: String)] {
        results.compactMap { result in
            if case .skipped(let reason) = result.outcome { return (result.resource, reason) }
            return nil
        }
    }

    public var summary: String {
        "\(importer): \(indexed.count) indexed, \(revised.count) revised, \(skipped.count) skipped"
    }
}

public struct IngestConfig: Sendable {
    /// How many *new* notes one run may create.
    ///
    /// A first pass over three hundred session files with no ceiling would add
    /// three hundred notes at once, which is the same mistake the janitor's
    /// review queue already taught this project once: a corpus that arrives
    /// faster than anyone can look at it trains its owner to stop looking.
    /// Leftovers are deferred to the next run, not dropped — the importers are
    /// deterministic, so the next run finds them again.
    public var noteBudget: Int

    public init(noteBudget: Int = 40) {
        self.noteBudget = noteBudget
    }
}

/// The hands of the data pipeline, and the reason it's safe to run on a
/// schedule with nobody watching.
///
/// Deliberately shaped like `JanitorRunner`, because it needs the same
/// guarantee. It calls exactly three `NoteService` methods — `createNote`,
/// `appendToNote`, `tagNote` — and nothing else that writes. It never archives,
/// never untags, never flags, never resolves a flag, and as everywhere in this
/// codebase has no delete available to it at all.
///
/// **It also never touches a note it did not author.** That restriction is
/// specific to this component and matters more here than it does for the
/// janitor: an importer generates note titles from filenames and session titles,
/// so a resource can perfectly well collide with a title a human already owns.
/// If it does, this skips the resource and says so. The alternative — appending
/// machine-generated index text onto someone's hand-written note because the
/// names matched — is the kind of quiet corruption there is no undo for, since
/// appends are events and events don't come back off the log.
///
/// What it deliberately does *not* do is judge. Ingesting adds raw material and
/// an index entry; deciding that two ingested notes are duplicates, or that one
/// is an orphan, is the janitor's job and reaches the human through the existing
/// review queue. That split is why this file needs no bucket logic of its own:
/// the buckets already exist, one layer down.
public final class IngestRunner {
    /// Every write this makes is attributed here, distinct from `"janitor"` and
    /// from any agent's name. A note that says `ingest` is a machine-built index
    /// entry, not a conclusion anything reasoned its way to — and the transaction
    /// log should always be able to tell those apart.
    public static let sourceIdentity = "ingest"

    private let service: NoteService
    private let rawStore: RawStore

    public init(service: NoteService, rawStore: RawStore) {
        self.service = service
        self.rawStore = rawStore
    }

    /// Runs one importer. Safe to call repeatedly: an unchanged resource that
    /// already has a note is skipped rather than re-indexed.
    @discardableResult
    public func run(importer: ResourceImporter, config: IngestConfig = IngestConfig()) throws -> IngestRunReport {
        let resources = try importer.discover()
        let notes = try service.listNotes(includeArchived: true)
        var mine = try noteIDsAuthoredByIngest()

        // Identity is the resource's `key`, never its title.
        //
        // Titles drift: a Claude session's `ai-title` is regenerated as the
        // conversation grows, so a title-keyed match minted a fresh permanent
        // note every time a session continued. A calibration run over the real
        // corpus caught it — one session id appearing across three notes whose
        // titles differed only in where the truncation fell.
        var byKey: [String: Note] = [:]
        var titles = Set(notes.map { $0.title.lowercased() })
        for note in notes where mine.contains(note.id) {
            if let key = IngestMarker.key(in: note.body) { byKey[key] = note }
        }

        var results: [(DiscoveredResource, IngestOutcome)] = []
        var spent = 0

        for resource in resources {
            let existing = byKey[resource.key]

            // A note we've never seen this key on, whose title is already taken.
            // Not ours to write into — see the type doc.
            if existing == nil, titles.contains(resource.title.lowercased()) {
                results.append((resource, .skipped(reason: "a note with this title already exists and wasn't created by ingest")))
                continue
            }

            // Archiving is how a human says "stop showing me this". Re-indexing
            // an archived note would quietly undo that, the same reason the
            // janitor skips archived notes entirely.
            if let note = existing, note.archived {
                results.append((resource, .skipped(reason: "note is archived")))
                continue
            }

            let ingested: (resource: RawResource, wasNew: Bool)
            do {
                ingested = try rawStore.ingest(contentsOf: resource.sourceURL)
            } catch {
                // One oversized or vanished file must not abort a bulk run.
                results.append((resource, .skipped(reason: "\(error)")))
                continue
            }
            let stamp = RawMarker.stamp(ingested.resource.digest)

            if let note = existing {
                // Same title, and the body already cites these exact bytes:
                // nothing has changed since the last run.
                guard !RawMarker.isStamped(note.body, with: ingested.resource.digest) else {
                    results.append((resource, .skipped(reason: "already indexed, unchanged")))
                    continue
                }
                let revised = try service.appendToNote(
                    id: note.id,
                    text: """
                    **Revised \(ImporterText.dayFormatter.string(from: Date()))** — the source file has \
                    changed since this was last indexed. The previous copy is still in `/raw`; \
                    nothing was replaced.

                    \(resource.summary)

                    **Raw:** `\(ingested.resource.storedName)` \(stamp)
                    """,
                    source: Self.sourceIdentity
                )
                byKey[resource.key] = revised
                results.append((resource, .revised))
                continue
            }

            guard spent < config.noteBudget else {
                results.append((resource, .skipped(reason: "note budget for this run is spent")))
                continue
            }

            let note = try service.createNote(
                title: resource.title,
                body: """
                \(resource.summary)

                **Raw:** `\(ingested.resource.storedName)` \(stamp) \(IngestMarker.stamp(resource.key))
                """,
                source: Self.sourceIdentity
            )
            for tag in resource.tags {
                try service.tagNote(id: note.id, tag: tag, source: Self.sourceIdentity)
            }
            byKey[resource.key] = note
            titles.insert(resource.title.lowercased())
            mine.insert(note.id)
            spent += 1
            results.append((resource, .indexed))
        }

        return IngestRunReport(
            importer: importer.identifier,
            results: results.map { (resource: $0.0, outcome: $0.1) }
        )
    }

    /// Discovers without writing anything — what a run *would* index.
    ///
    /// The janitor's "Preview" is listed before "Run now" in the UI on purpose,
    /// and this exists so the same promise can be made here: you can always see
    /// what a pipeline would pull in before it pulls anything in. That matters
    /// more for ingest than for the janitor, because these importers read the
    /// user's own files.
    public func preview(importer: ResourceImporter) throws -> [DiscoveredResource] {
        try importer.discover()
    }

    // MARK: - Private

    /// Every note whose `created` event was written by this component.
    ///
    /// Read from the raw event log rather than the projection because
    /// `Note.sources` is a *set* of everyone who ever wrote to a note — it can't
    /// answer "who created this", which is the only question that matters here.
    /// A note an agent created and ingest later appended to would look identical
    /// to one ingest created, and appending index text onto an agent's note is
    /// exactly what this guard exists to prevent.
    private func noteIDsAuthoredByIngest() throws -> Set<UUID> {
        var ids: Set<UUID> = []
        for event in try service.transactionLog(limit: Int.max)
        where event.kind == .created && event.source == Self.sourceIdentity {
            ids.insert(event.noteId)
        }
        return ids
    }
}

/// Formats and recognises the marker tying a note to the bytes in `/raw` it was
/// built from. The same trick as `JanitorMarker`: identity carried in the text,
/// so idempotence survives without a second store to keep in sync with the log.
enum RawMarker {
    static func stamp(_ digest: String) -> String { "[raw:\(RawStore.digestPrefix(digest))]" }

    static func isStamped(_ body: String, with digest: String) -> Bool {
        body.contains(stamp(digest))
    }
}
