import Foundation

/// Keeps `outboundLinks` / `backlinks` / `danglingLinks` current as events
/// arrive, touching only the notes whose answer can have changed.
///
/// **Why this exists.** `Projector.resolveLinks` rebuilds every note's links
/// from every note's body. That's the right shape for a cold projection and the
/// wrong shape for an incremental one: run it after each write and the cost per
/// write is proportional to the size of the corpus, which is a quadratic ingest
/// wearing an incremental disguise.
///
/// Worth recording because it was the wrong guess: caching the *parse* was tried
/// first and barely helped — measured over 400 notes it took a 1.00s run to
/// 0.84s. The expense was never the bracket-scanning. It was rebuilding n sets
/// and re-sorting n titles on every one of 800 writes, which no amount of
/// faster parsing addresses.
///
/// What actually changes when an event lands is small and knowable:
///
/// - A **changed body** changes that note's own links, and only that note's.
/// - A **new note** can satisfy links that were dangling on its title (or on its
///   raw UUID) — and those notes are findable directly, because dangling links
///   are indexed here rather than searched for.
/// - Everything else — a tag, an archive, a flag, a resolved review — cannot
///   change any link at all, so it costs nothing.
///
/// The result is exact, not approximate: `ProjectionCacheTests` asserts the
/// incremental answer equals a cold `Projector.project` of the same log, which
/// is the only property that matters here. If the two ever disagree, trust the
/// cold one and fix this.
struct LinkIndex {
    /// The oldest note to claim a title owns it, matching
    /// `Projector.resolveLinks`'s "oldest wins, ties broken by id".
    ///
    /// This used to claim in *arrival* order, on the reasoning that arrival and
    /// `createdAt` order are the same thing for a log written in real time. They
    /// are — right up until a second device appears. An event captured offline
    /// and imported later arrives after events that happened before it, and then
    /// the incumbent-wins rule hands the title to the *newer* note while a cold
    /// `Projector.project` hands it to the older one. `ShardImportTests` pins it.
    ///
    /// So a later arrival with an older `createdAt` displaces the incumbent, and
    /// everything that resolved to the incumbent is recomputed.
    private var idsByTitle: [String: UUID] = [:]

    /// Each note's `[[…]]` targets as last parsed from its body.
    private var parsedTargets: [UUID: [String]] = [:]

    /// Lowercased unresolved target → the notes currently dangling on it. This
    /// is what makes "a new note fixes old dangling links" a lookup instead of a
    /// scan, and it's the whole reason a create is cheap.
    private var danglingBy: [String: Set<UUID>] = [:]

    mutating func reset() {
        idsByTitle = [:]
        parsedTargets = [:]
        danglingBy = [:]
    }

    /// Brings `notes` up to date after a fold.
    ///
    /// `created` and `bodiesChanged` come straight from the event kinds in the
    /// batch — `.created` and `.appended` are the only two that can touch a body
    /// or introduce a title.
    mutating func update(_ notes: inout [UUID: Note], created: [UUID], bodiesChanged: [UUID]) {
        var dirty = Set(bodiesChanged)

        for id in created {
            guard let note = notes[id] else { continue }
            dirty.insert(id)

            let titleKey = note.title.lowercased()
            if let incumbentID = idsByTitle[titleKey] {
                // Same tie-break as Projector.resolveLinks: (createdAt, id).
                let incumbent = notes[incumbentID]
                let claims = incumbent.map {
                    (note.createdAt, note.id.uuidString) < ($0.createdAt, $0.id.uuidString)
                } ?? true
                if claims {
                    idsByTitle[titleKey] = id
                    dirty.formUnion(danglingBy[titleKey] ?? [])
                    // Whatever pointed at the incumbent has to be re-resolved —
                    // some of it was resolving by this title and now lands here.
                    dirty.formUnion(incumbent?.backlinks ?? [])
                }
            } else {
                idsByTitle[titleKey] = id
                // Anything that was dangling on this title now resolves.
                dirty.formUnion(danglingBy[titleKey] ?? [])
            }
            // …and anything that linked to it by raw UUID before it existed.
            dirty.formUnion(danglingBy[id.uuidString.lowercased()] ?? [])
        }

        for id in dirty {
            guard let note = notes[id] else {
                forget(id)
                continue
            }
            retract(note, id: id, from: &notes)
            parsedTargets[id] = WikiLink.targets(in: note.body)
            apply(id: id, to: &notes)
        }
    }

    // MARK: - Private

    /// Undoes what this note currently contributes, so the recompute below is
    /// a replacement rather than an accumulation. A stale backlink is a
    /// relationship the corpus no longer contains.
    private mutating func retract(_ note: Note, id: UUID, from notes: inout [UUID: Note]) {
        for target in note.outboundLinks {
            notes[target]?.backlinks.remove(id)
        }
        for target in note.danglingLinks {
            danglingBy[target.lowercased()]?.remove(id)
        }
    }

    private mutating func apply(id: UUID, to notes: inout [UUID: Note]) {
        var outbound: Set<UUID> = []
        var dangling: Set<String> = []

        for target in parsedTargets[id] ?? [] {
            if let uuid = UUID(uuidString: target), notes[uuid] != nil {
                outbound.insert(uuid)
            } else if let match = idsByTitle[target.lowercased()] {
                outbound.insert(match)
            } else {
                dangling.insert(target)
            }
        }

        outbound.remove(id) // a note citing itself isn't a relationship

        notes[id]?.outboundLinks = outbound
        notes[id]?.danglingLinks = dangling
        for target in outbound {
            notes[target]?.backlinks.insert(id)
        }
        for target in dangling {
            danglingBy[target.lowercased(), default: []].insert(id)
        }
    }

    private mutating func forget(_ id: UUID) {
        parsedTargets.removeValue(forKey: id)
    }
}
