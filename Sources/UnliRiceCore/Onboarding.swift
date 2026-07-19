import Foundation

/// What a brand-new install gets instead of an empty list and a silent janitor.
///
/// A user with zero notes can't discover two things from the UI alone: what a
/// note here is *for*, and that tags are freeform vocabulary the janitor only
/// reuses once it's already established elsewhere (`JanitorConfig.
/// minimumTagCorpusUse`). Both matter together — on a truly empty corpus the
/// janitor has nothing to reuse *no matter how much the user writes*, since
/// every cosmetic tag proposal requires the tag to already sit on a couple of
/// other notes. Two short notes fix both at once: they're readable in under a
/// minute, and both tagging "guide" gives the janitor exactly the usage count
/// Eco/Balanced require, so the feature demonstrates itself on first launch
/// instead of staying invisible until the user stumbles into tagging by hand.
public enum Onboarding {
    /// The tag the seed notes share — deliberately not a name a real note would
    /// likely reach for on its own, so it doesn't get proposed onto unrelated
    /// notes later just because "guide" happens to appear in their text too
    /// often. (Contrast: PROJECT_NOTES.md's "memory" saturation problem.)
    public static let seedTag = "guide"

    /// Writes the two seed notes if — and only if — this corpus has never been
    /// seeded and is currently empty.
    ///
    /// The emptiness check is what keeps this from ever touching a migrated
    /// pre-rename log or any corpus a human or agent already wrote into: by the
    /// time this runs, `DataLocation`'s migration (if any) has already
    /// happened, so an empty `listNotes` here means the corpus really is new,
    /// not merely new *at this path*.
    ///
    /// `hasSeeded`/`markSeeded` are injected rather than hardcoded to
    /// `UserDefaults` so this stays testable without touching real user
    /// defaults, and so a user who archives both notes doesn't get them
    /// reinjected on the next launch — this is a one-time seed, not a
    /// standing invariant.
    @discardableResult
    public static func seedIfNeeded(
        service: NoteService,
        hasSeeded: () -> Bool,
        markSeeded: () -> Void
    ) throws -> Bool {
        guard !hasSeeded() else { return false }
        defer { markSeeded() }
        guard try service.listNotes(includeArchived: true).isEmpty else { return false }

        let welcome = try service.createNote(title: "Welcome to Unli Rice", body: welcomeBody, source: Self.source)
        try service.tagNote(id: welcome.id, tag: seedTag, source: Self.source)

        let tagging = try service.createNote(
            title: "How tags and the janitor work", body: taggingBody, source: Self.source
        )
        try service.tagNote(id: tagging.id, tag: seedTag, source: Self.source)

        return true
    }

    /// Distinct from `"human"` and from any connected agent's name, so these
    /// two notes are visibly the app's own voice in the transaction log, not
    /// something a person or an LLM wrote.
    public static let source = "unlirice"

    static let welcomeBody = """
    This is a note. Anything you write here — and anything an AI agent \
    connected over MCP writes here (Claude, ChatGPT, Gemini, a coding \
    assistant) — lands in the same shared memory. Nothing is ever silently \
    deleted; the closest thing to delete is Archive, in the sidebar, which is \
    fully reversible.

    Two habits that make this useful over time rather than just a pile of \
    one-shot notes:

    - Prefer appending to an existing note over starting a new one with a \
    similar title. Two near-identical notes just make each other harder to \
    find later — open a note and use "Add to this note" at the bottom.
    - Link to another note by writing [[Its Exact Title]] anywhere in a \
    note's body. It works even if that note doesn't exist yet — the link \
    just shows as unresolved until it does.

    Next: "How tags and the janitor work."
    """

    static let taggingBody = """
    Tags aren't a fixed list built into the app — they're whatever word you \
    or an agent decides is useful, the same way this note's own "guide" tag \
    got here. The janitor, in the panel on the right, can only reuse a tag \
    once it's already used on a couple of other notes *and* appears in a new \
    note's own text. On a brand-new corpus that means it has nothing to work \
    with — which is exactly why this note and "Welcome to Unli Rice" are both \
    tagged "guide": it gives the janitor something to learn from immediately, \
    instead of staying silent until you've manually tagged a few notes \
    yourself.

    The janitor only ever does two things, and nothing else: quietly add a \
    tag like this one (reversible with one click), or flag a possible \
    duplicate or typo for you to decide on in the Review Queue. It never \
    merges, deletes, or edits a note without your say. Press Preview any \
    time to see exactly what it would do before running it for real.
    """
}
