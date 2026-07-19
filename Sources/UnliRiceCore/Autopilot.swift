import Foundation

/// Get Started, after the local-model interview was cut.
///
/// The interview is gone because it didn't work. Qwen3-1.7B was asked to run a
/// four-topic conversation and, on a real first run, emitted its finish marker
/// after a single answer — producing a setup prompt with no stack, no tool and
/// no conventions in it. That isn't a prompt-tuning bug to iterate on; it's the
/// same conclusion PROJECT_NOTES.md already reached twice about this model
/// class, arrived at a third time. Nothing here calls a model now, and the flow
/// is better for it: every step is deterministic, instant, and testable.
///
/// What replaces it is the thing the user actually needed — getting an MCP
/// client connected. See `MCPTarget` for the catalog and `MCPConfigWriter` for
/// the rules around editing a config this app didn't create.
public enum Autopilot {
    // MARK: - Finding the package

    /// Shown in place of a real path when detection fails, so the block stays
    /// copyable and the one thing needing a human edit is obvious.
    public static let packagePathPlaceholder = "/absolute/path/to/Unli Rice"

    /// Walks up from `start` looking for the directory containing
    /// `Package.swift`.
    ///
    /// Resolves for the real app because `Scripts/mlx-run` pins
    /// `-derivedDataPath .build/xcode` *inside* the repo before building, so the
    /// product is a descendant of the package root. Verified against the real
    /// build output, which is a bare executable rather than a `.app` — meaning
    /// `Bundle.main.bundleURL` is the containing directory; the walk resolves
    /// either way. `fileExists` is injected so the walk can be tested against a
    /// made-up tree.
    public static func packageRoot(
        startingAt start: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        var directory = start.standardizedFileURL
        while directory.path != "/" && !directory.path.isEmpty {
            if fileExists(directory.appendingPathComponent("Package.swift")) {
                return directory
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            guard parent != directory else { break }
            directory = parent
        }
        return nil
    }

    /// The package root for the running app, or `nil` if it can't be found — in
    /// which case the UI shows a placeholder rather than emitting a confidently
    /// wrong path into a config the user is about to rely on.
    public static func detectedPackageRoot() -> URL? {
        packageRoot(startingAt: Bundle.main.bundleURL)
    }

    // MARK: - The house-rules note

    /// The tag the Autopilot note carries. Gives a brand-new corpus an
    /// established tag from its first note, the same cold-start reason
    /// `Onboarding.seedTag` exists — the janitor's cosmetic rule can only reuse
    /// a tag that is already in use elsewhere.
    public static let noteTag = "how-to"

    public static let noteTitleBase = "How to use these notes"

    /// Titles are permanent and wiki-links resolve by exact title (AGENTS.md),
    /// so a second run must not produce a second note with the same name —
    /// `[[How to use these notes]]` would be ambiguous forever. Get Started is
    /// reachable from the sidebar at any time, so a repeat run is a normal path.
    public static func noteTitle(existingTitles: [String]) -> String {
        let taken = Set(existingTitles.map { $0.lowercased() })
        guard taken.contains(noteTitleBase.lowercased()) else { return noteTitleBase }
        var suffix = 2
        while taken.contains("\(noteTitleBase) \(suffix)".lowercased()) { suffix += 1 }
        return "\(noteTitleBase) \(suffix)"
    }

    /// The note Autopilot writes, addressed to the assistant rather than to the
    /// user.
    ///
    /// This is what makes the loop close by itself. It lands in the note store,
    /// so the first thing any connected tool finds when it calls `list_notes` is
    /// an instruction to keep reading and writing notes — which is precisely the
    /// habit someone new to the second-brain idea has no way to know they need.
    /// Written as plain standing instructions because that's what a capable
    /// model will act on; nothing enforces it, and nothing here can.
    public static let noteBody = """
    Instructions for any AI assistant connected to these notes over the \
    `unlirice` MCP server. Read this first.

    **At the start of every session**, call `list_notes` (or `search_notes` for \
    something specific) before you begin work. These notes are the memory you \
    don't otherwise have — decisions, context, and conventions from previous \
    sessions live here, possibly written by a different tool than you.

    **At the end of every session**, record what's worth keeping. Use \
    `append_to_note` to add to an existing note whenever one already covers the \
    topic, and `create_note` only when it genuinely doesn't. Prefer appending: \
    two near-duplicate notes make each other harder to find later.

    **Always pass your own tool name, lowercase, as `source`** — `claude`, \
    `codex`, `cursor`, and so on. That's the only thing making this history \
    attributable once several tools have written into it. Never write as \
    `janitor`; that name belongs to this app's own background helper.

    **Titles are permanent.** There is no rename, on purpose — `[[Exact Title]]` \
    in any note body links to the note with that title, so a title that could \
    change would break links silently. Choose them like they're permanent.

    **Nothing here is ever deleted.** `archive_note` is soft and fully \
    reversible, and it's the closest thing to a delete that exists. Don't treat \
    it as one, and don't ask for a delete tool — there isn't one by design.
    """
}
