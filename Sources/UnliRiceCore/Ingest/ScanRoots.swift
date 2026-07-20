import Foundation

/// Keeps the set of nominated folders non-overlapping.
///
/// Any folder is a legitimate root — Documents, Desktop, a single project, a
/// vault. What isn't legitimate is two roots where one contains the other, and
/// that's easy to arrive at innocently: add an Obsidian vault, then later add
/// the Documents folder it lives in.
///
/// Overlap isn't merely wasteful. `LocalFileImporter.disambiguate` appends a
/// hash suffix to any title it sees more than once in a run, so the same file
/// found under two roots looks like two different documents that happen to share
/// a name — and it would take that suffix *permanently*, because titles in this
/// store can never be renamed. The file would also be walked, read, and
/// size-checked twice on every run for no benefit.
///
/// So the rule is: the broadest folder wins. Adding a parent replaces the
/// children it already covers; adding a child of an existing root does nothing
/// but say so.
public enum ScanRoots {
    public struct Change: Equatable {
        /// The new set, after the addition.
        public let roots: [URL]
        /// Roots dropped because the folder being added already contains them.
        public let removed: [URL]
        /// Set when the addition was a no-op because an existing root already
        /// covers it. Carries the root that covers it, for the message.
        public let alreadyCoveredBy: URL?

        public var didChange: Bool { alreadyCoveredBy == nil }
    }

    /// Normalises first: a path typed with a trailing slash, reached through a
    /// symlink, or containing `..` is the same folder, and comparing raw URLs
    /// would let the same directory in twice under two spellings.
    public static func adding(_ folder: URL, to roots: [URL]) -> Change {
        let candidate = normalize(folder)
        let existing = roots.map(normalize)

        if let covering = existing.first(where: { candidate == $0 || candidate.isInside($0) }) {
            return Change(roots: roots, removed: [], alreadyCoveredBy: covering)
        }

        let subsumed = existing.filter { $0.isInside(candidate) }
        let kept = zip(roots, existing).filter { !subsumed.contains($0.1) }.map(\.0)
        return Change(roots: kept + [candidate], removed: subsumed, alreadyCoveredBy: nil)
    }

    public static func normalize(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }
}

extension URL {
    /// Strict containment, compared component-wise rather than by string prefix
    /// — `/Users/me/Notes2` has `/Users/me/Notes` as a string prefix while being
    /// an entirely unrelated folder.
    func isInside(_ other: URL) -> Bool {
        let mine = standardizedFileURL.pathComponents
        let theirs = other.standardizedFileURL.pathComponents
        guard mine.count > theirs.count else { return false }
        return Array(mine.prefix(theirs.count)) == theirs
    }
}
