import Foundation

/// Preset overlay you can drop into any profile's Overlays step, independent
/// of which full `ProfileTemplate` (if any) was loaded. Where `ProfileTemplate`
/// bundles a whole profile, this bundles just one overlay note — so a Swift
/// overlay can be added on top of the Writer/Researcher template, or any
/// other combination.
public struct OverlayTemplate: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var summary: String
    public var rules: String

    public init(id: String, title: String, summary: String, rules: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.rules = rules
    }

    /// A fresh `OverlayEntry` from this template — new UUID each call, so
    /// applying the same template twice (or alongside a hand-written overlay
    /// of the same name) never collides on identity.
    public func makeEntry() -> ProfileBuilderInput.OverlayEntry {
        ProfileBuilderInput.OverlayEntry(name: title, rules: rules)
    }

    public static let builtIn: [OverlayTemplate] = [
        OverlayTemplate(
            id: "swift",
            title: "Swift",
            summary: "Concurrency, optionals, types, and testing rules for Swift/SwiftUI work.",
            rules: """
            Match the file's existing concurrency model — don't introduce async/await into completion-handler code (or vice versa) without being asked to migrate it. Shared mutable state only through actor isolation or @MainActor; never touch it from a background queue directly. Force-unwrap (!) and force-cast (as!) only where failure is provably impossible — never on network, disk, or user input; try? never swallows an error that matters. Value types (struct/enum) by default; class only for genuine reference-identity needs. Run `swift build && swift test` before declaring any change done. New logic ships with a test in the same commit, not as a follow-up.
            """
        ),
        OverlayTemplate(
            id: "web-frontend",
            title: "Web / Frontend",
            summary: "Semantic HTML, accessibility, and no-tracker defaults for frontend work.",
            rules: """
            Semantic HTML first — no div-soup where a native element already does the job. No client-side framework unless the interaction genuinely needs one; plain HTML/CSS/JS is the default. Accessibility (labels, focus order, contrast, keyboard navigation) ships in the first draft, not as a retrofit. No trackers, no third-party analytics scripts. Verify in an actual browser before declaring a change done — a build pass is not a visual or interaction check.
            """
        ),
        OverlayTemplate(
            id: "python",
            title: "Python",
            summary: "Typing, dependency hygiene, and test rules for Python work.",
            rules: """
            Type hints on every public function signature; no untyped `def` in library code. Keep the lockfile (requirements.txt / pyproject) in sync with what's actually imported — no phantom or unused dependencies. No bare `except:` — catch specific exceptions or let the error propagate. Run the test suite before declaring any change done. Prefer f-strings over `.format()`/`%`, and `pathlib` over `os.path`, in new code.
            """
        ),
        OverlayTemplate(
            id: "data-backend",
            title: "Data / Backend",
            summary: "Migration safety, idempotency, and query-safety rules for backend/data work.",
            rules: """
            Every schema migration is additive and reversible — no destructive change without an explicit rollback path. Never run a write against production data without a dry-run or a transaction wrapping it first. Queries touching user data are always parameterized, never string-interpolated. Jobs log what they did (rows affected, duration), not just that they ran. Jobs are idempotent by default, so a run that fails partway can safely re-run without double-applying.
            """
        )
    ]
}
