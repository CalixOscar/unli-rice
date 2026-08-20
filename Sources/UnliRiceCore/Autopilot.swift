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
/// client connected. See `MCPTarget` for the catalog and
/// `MCPConfigRenderer` for the paste-ready config renderer.
public enum Autopilot {
    // MARK: - Finding the package

    /// Shown in place of a real path when detection fails, so the block stays
    /// copyable and the one thing needing a human edit is obvious.
    public static let packagePathPlaceholder = "/absolute/path/to/Unli Rice"

    /// Walks up from `start` looking for the directory containing
    /// `Package.swift`.
    ///
    /// Resolves for the real app because SwiftPM builds into `.build/` *inside*
    /// the package, so the product is always a descendant of the package root.
    /// (This used to depend on `Scripts/mlx-run` pinning `-derivedDataPath
    /// .build/xcode` for the same reason; that script is gone with MLX, and
    /// plain `swift build` gives the property for free.) Verified against the
    /// real build output, which is a bare executable rather than a `.app` —
    /// meaning `Bundle.main.bundleURL` is the containing directory; the walk
    /// resolves either way. `fileExists` is injected so the walk can be tested
    /// against a made-up tree.
    ///
    /// Note this would stop holding if the app were ever shipped as a bundle in
    /// `/Applications` — there is no `Package.swift` above that. The nil return
    /// is already handled (the UI shows a placeholder path rather than a
    /// confidently wrong one), but it becomes the normal case, not the edge one.
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

    // MARK: - Finding *any* enclosing project

    /// Filenames that, on their own, mean "this directory is a project root".
    static let projectMarkerNames = [
        ".git",
        "Package.swift",
        "package.json",
        "pyproject.toml",
        "Cargo.toml",
        "go.mod",
        "CLAUDE.md"
    ]

    /// Extensions matched against directory entries, since these carry the
    /// project's own name (`Foo.xcodeproj`) and can't be checked by exact path.
    static let projectMarkerExtensions = ["xcodeproj", "xcworkspace"]

    /// Walks up from `start` looking for the first directory that carries any
    /// evidence of being a project root.
    ///
    /// Deliberately separate from `packageRoot`, which answers a narrower and
    /// still-needed question — "where is the SwiftPM package?" — and is used
    /// that way to build a `swift run --package-path` invocation. This one only
    /// answers "is the user sitting inside *some* project?", so it accepts
    /// Xcode-only projects, plain git checkouts, and non-Swift codebases too.
    ///
    /// The MCP server's `initialize` instructions previously asked `packageRoot`
    /// that question and told every Xcode-only or non-Swift session it had no
    /// project — while the assistant was mid-edit on a file in one.
    ///
    /// `fileExists` and `contentsOfDirectory` are injected so the walk can be
    /// tested against a made-up tree.
    public static func enclosingProjectRoot(
        startingAt start: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        contentsOfDirectory: (URL) -> [String] = {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? []
        }
    ) -> URL? {
        var directory = start.standardizedFileURL
        while directory.path != "/" && !directory.path.isEmpty {
            if projectMarkerNames.contains(where: {
                fileExists(directory.appendingPathComponent($0))
            }) {
                return directory
            }
            if contentsOfDirectory(directory).contains(where: {
                projectMarkerExtensions.contains(URL(fileURLWithPath: $0).pathExtension)
            }) {
                return directory
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            guard parent != directory else { break }
            directory = parent
        }
        return nil
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

    **At the start of every session**, use `search_notes` to look for `Wiki: \
    index`. If it exists, read it first and follow the hub relevant to the task. \
    If it does not exist, search for the specific topic directly. Use \
    `list_notes` only when the store is small or you genuinely need an overview. \
    These notes are memory shared by several tools, not a replacement for \
    current evidence.

    **At the end of every session**, record what's worth keeping. Use \
    `append_to_note` to add to an existing note whenever one already covers the \
    topic, and `create_note` only when it genuinely doesn't. Prefer appending: \
    two near-duplicate notes make each other harder to find later.

    **Maintain an existing wiki layer.** If a substantial addition changes what \
    exists for a topic or where its authority lives, update the relevant `Wiki: \
    <topic>` hub in the same session. Hubs are tables of contents, not essays. \
    If this store has no wiki layer, do not invent one merely to satisfy this rule.

    **Always pass your own tool name, lowercase, as `source`** — `claude`, \
    `codex`, `cursor`, and so on. That's the only thing making this history \
    attributable once several tools have written into it. Never write as \
    `janitor` or `ingest`; those names belong to the app's background helper \
    and ingestion pipelines.

    **Titles are permanent.** There is no rename, on purpose — `[[Exact Title]]` \
    in any note body links to the note with that title, so a title that could \
    change would break links silently. Choose them like they're permanent.

    **Nothing here is ever deleted.** `archive_note` is soft and fully \
    reversible, and it's the closest thing to a delete that exists. Don't treat \
    it as one, and don't ask for a delete tool — there isn't one by design.

    **Never resolve a conflict autonomously.** If two notes appear to duplicate \
    or contradict one another, call `flag_for_review` with the evidence and stop. \
    A human decides whether to merge, archive, or resolve the flag.

    **Exception Guardrail.** If the user asks for something that contradicts \
    these notes, ask whether it's a one-time exception or whether the note should \
    change. One-time → note the exception in the session; change → append the change \
    to the relevant note.

    **AI-Led Profile Setup.** At the start of your first session with the user, \
    if `Profile: identity` does not exist yet, ask the user a few brief questions \
    about themselves (their identity, preferred communication voice, core principles, \
    and guardrails), and record their answers as `Profile: identity`, `Profile: voice`, \
    `Profile: principles`, and `Profile: guardrails` notes into Unli Rice.

    **Maintain Memory Capsule.** At session end, rewrite `Memory: capsule` as a fresh append, \
    ≤2,500 characters, containing only what a cold-start LLM must know about the user and their active projects.
    """
}
