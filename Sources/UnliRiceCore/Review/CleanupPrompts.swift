import Foundation

/// Canned instructions a human hands to whichever LLM is already connected,
/// rather than actions this app performs itself.
///
/// The distinction is the entire point. Every job described here — deciding
/// which of four near-identical ingest notes is worth keeping, judging whether
/// two notes are the same idea, working out what a year-old note was for — is
/// exactly the kind of judgement decision #3 in PROJECT_NOTES.md says an agent
/// proposes and a human approves. Building a "Delete all ingest" button into
/// the GUI would make the app the thing that decides; putting the same sentence
/// on the clipboard makes the agent do the reading and still leaves every
/// individual write reversible, attributable to that agent's `source`, and
/// visible in the transaction log.
///
/// The prompt bodies name real tools (`list_notes`, `archive_note`, …) because
/// a vague prompt produces a chatty answer instead of work. They also all state
/// the archive-not-delete rule explicitly: a model that has not read AGENTS.md
/// will otherwise reach for deletion it does not have, and report success it
/// did not achieve.
public struct CleanupPrompt: Identifiable, Equatable, Sendable {
    public let id: String
    /// Button label. Short enough to read as an action.
    public let title: String
    /// One line under the label — what it will do, in the user's terms.
    public let blurb: String
    /// The text that lands on the clipboard.
    public let body: String

    public init(id: String, title: String, blurb: String, body: String) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.body = body
    }
}

public enum CleanupPrompts {
    /// The shared preamble. Repeated into every prompt rather than assumed,
    /// because these get pasted into a fresh chat with no other context — the
    /// receiving model may never have seen this project's AGENTS.md.
    private static let houseRules = """
    You have the `unlirice` MCP server connected. Ground rules for this store:
    - It is append-only. There is no delete tool. `archive_note` is the strongest \
    thing you have, and it is reversible with `unarchive_note`.
    - Note titles are permanent — there is no rename. If two notes are the same \
    idea, append the newer one's content onto the older one and archive the newer.
    - Never merge or archive anything you are unsure about. Use `flag_for_review` \
    to raise it for me instead, and say so in your summary.
    - Tell me what you changed at the end: counts, and the titles of anything archived.
    """

    /// Offered from Review Notes — the pile that already exists.
    public static let review: [CleanupPrompt] = [
        CleanupPrompt(
            id: "clear-ingest",
            title: "Clear out ingested sessions",
            blurb: "Archives auto-imported session logs that never turned into anything.",
            body: """
            \(houseRules)

            Task: the notes whose source is "ingest" were imported automatically from \
            my coding-session transcripts. Most are noise; a few contain a decision worth \
            keeping.

            Go through them with `list_notes` and `get_note`. For each one, decide whether \
            it records anything I would want to find again — a decision, a fix, a \
            constraint, a preference. If it does, leave it alone and tag it "keep". If it \
            is just a transcript of routine work, `archive_note` it with the reason \
            "ingested session, no durable content".

            Do not archive anything that other notes link to. Report how many you kept and \
            how many you archived.
            """
        ),
        CleanupPrompt(
            id: "dedupe",
            title: "Resolve duplicates",
            blurb: "Finds notes that say the same thing and folds them together.",
            body: """
            \(houseRules)

            Task: find duplicate and near-duplicate notes and consolidate them.

            Use `list_notes` and `search_notes` to find notes covering the same subject. \
            For each cluster you are confident about: pick the oldest note as the keeper, \
            `append_to_note` anything the others say that it does not already say, then \
            `archive_note` the others with a reason naming the keeper.

            If a cluster looks like a duplicate but the notes actually disagree with each \
            other, do not merge them — `flag_for_review` the keeper describing the \
            conflict, and leave both in place.
            """
        ),
        CleanupPrompt(
            id: "tag-and-sort",
            title: "Consolidate and sort",
            blurb: "Gives untagged notes a consistent vocabulary and links related ones.",
            body: """
            \(houseRules)

            Task: make this store navigable.

            1. `list_notes` and read what is actually here. Work out the handful of tags \
            that describe this corpus — reuse tags that already exist rather than \
            inventing synonyms for them.
            2. Tag untagged notes with `tag_note`. Two or three tags each, no more. Do not \
            apply a tag to a note just because the word appears in its text.
            3. Where one note clearly refers to a subject that has its own note, \
            `append_to_note` a `[[Exact Note Title]]` wiki-link so they connect in the graph.

            Report the tag vocabulary you settled on and how many notes you touched.
            """
        ),
        CleanupPrompt(
            id: "whats-stale",
            title: "What's gone stale?",
            blurb: "Reads for facts that have since been overtaken, and flags them.",
            body: """
            \(houseRules)

            Task: find notes that are no longer true.

            Read through the store and look for statements that later notes contradict, \
            plans that were clearly abandoned, and instructions that reference tools, \
            paths, or decisions that other notes say have since changed.

            Do not archive these — being outdated is not the same as being worthless, and \
            the history matters. For each one, `append_to_note` a dated line saying what \
            superseded it and linking the note that did, then `flag_for_review` it so I see \
            it in my queue.
            """
        )
    ]

    /// Offered from Archived, where the question is narrower: of the things I
    /// already set aside, is any of it safe to lose for good?
    public static let archive: [CleanupPrompt] = [
        CleanupPrompt(
            id: "review-archive",
            title: "Review what's archived",
            blurb: "Asks the LLM which archived notes are safe to trash, and which to restore.",
            body: """
            \(houseRules)

            Task: I have archived the notes listed by `list_notes` with archived included. \
            Archiving is reversible, so this pile has accumulated without much thought. \
            Help me sort it.

            Read each archived note and put it in one of three buckets:
            - RESTORE — this still matters and should not be archived. Use `unarchive_note`.
            - KEEP ARCHIVED — dated, but worth being able to find. Leave it.
            - SAFE TO TRASH — genuinely worthless: empty, a duplicate of a note that \
            survived, or a transcript of nothing. Do NOT act on these. List the titles \
            for me and I will do it by hand.

            The third bucket is the only one where you must not act, because trashing is \
            the one operation in this system that a human has to perform. Give me that \
            list with a one-line reason each.
            """
        )
    ]
}
