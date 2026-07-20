import Foundation

/// Pulls prose documents out of folders the user has explicitly nominated.
///
/// **There is no default root, and that is the design.** The video this pipeline
/// comes from says "scan your computer"; this asks which folders instead. A
/// scanner that starts at `~` would copy a decade of unrelated documents into
/// `/raw` and index them under the user's name, and no one reviewing a corpus of
/// four thousand notes can tell which ones they meant to add. `roots` is
/// non-optional with no fallback, so "scan everything" isn't a state this type
/// can be left in by accident.
///
/// Only prose is taken. Source code is deliberately excluded: it already lives
/// in version control, it's the thing an agent can read directly when it needs
/// to, and indexing it would bury the documents that actually carry decisions.
public struct LocalFileImporter: ResourceImporter {
    public let identifier = "local-file"
    public let displayName = "Local documents"

    /// Prose formats only — see the type doc for why code is absent.
    public static let defaultExtensions: Set<String> = ["md", "markdown", "txt", "text", "rst", "org"]

    /// Directories that are build output, dependency caches, or version-control
    /// internals. Descending into these finds thousands of vendored READMEs that
    /// nobody wrote and nobody wants indexed.
    public static let skippedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "DerivedData", "Pods",
        "vendor", "venv", ".venv", "__pycache__", ".next", ".nuxt", ".cache",
        "dist", "build", "target", "Carthage", ".terraform", "site-packages"
    ]

    /// Drop a file with this name into a folder and the walk skips that folder
    /// and everything under it.
    ///
    /// `skippedDirectories` can only ever cover directories that are junk *by
    /// name*, which is a fine rule for `node_modules` and a useless one for
    /// "this is my archive of a system I retired". That case is about meaning,
    /// not naming, and only the person who retired it knows. The alternatives
    /// were worse: a settings list of excluded paths is invisible from the
    /// folder it governs and rots the moment anything is renamed, and hiding a
    /// folder with a leading dot to exploit `skipsHiddenFiles` hides it from the
    /// user in Finder too, which is a real cost paid to a side effect.
    ///
    /// A marker file travels with the folder, survives renames and moves, is
    /// discoverable by anyone who opens the folder, and is removed by deleting
    /// it. The contents are never read — its presence is the whole signal — so
    /// it is a good place to write down why.
    public static let ignoreMarkerFilename = ".unliriceignore"

    private let roots: [URL]
    private let extensions: Set<String>
    private let maximumDepth: Int
    private let maximumFilesPerRoot: Int
    private let minimumBytes: Int
    private let maximumBytes: Int
    private let fileManager: FileManager

    public init(
        roots: [URL],
        extensions: Set<String> = LocalFileImporter.defaultExtensions,
        maximumDepth: Int = 6,
        maximumFilesPerRoot: Int = 300,
        minimumBytes: Int = 200,
        maximumBytes: Int = 5 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        self.roots = roots
        self.extensions = extensions
        self.maximumDepth = maximumDepth
        self.maximumFilesPerRoot = maximumFilesPerRoot
        self.minimumBytes = minimumBytes
        self.maximumBytes = maximumBytes
        self.fileManager = fileManager
    }

    public func discover() throws -> [DiscoveredResource] {
        var found: [DiscoveredResource] = []
        // One resource per file, even if two roots reach it. `ScanRoots` keeps
        // the nominated folders non-overlapping, but a symlink can still lead
        // two unrelated roots to the same file, and `disambiguate` below would
        // read that as a name collision and brand the file with a permanent
        // hash suffix. Path is already this resource's identity (see `key`).
        var seen: Set<String> = []
        for root in roots {
            for resource in discover(in: root) where seen.insert(resource.sourceURL.path).inserted {
                found.append(resource)
            }
        }
        return disambiguate(found).sorted { $0.occurredAt > $1.occurredAt }
    }

    /// The marker only ever suppresses; it can't pull in a file the walk would
    /// otherwise have skipped. That asymmetry is deliberate — a stray file in a
    /// folder should never be able to *widen* what gets indexed.
    private func isIgnored(_ directory: URL) -> Bool {
        fileManager.fileExists(
            atPath: directory.appendingPathComponent(Self.ignoreMarkerFilename).path
        )
    }

    private func discover(in root: URL) -> [DiscoveredResource] {
        // The enumerator yields a root's *contents*, never the root itself, so a
        // marker sitting in the nominated folder would otherwise be ignored by
        // the one check that should honour it most.
        guard !isIgnored(root) else { return [] }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootDepth = root.standardizedFileURL.pathComponents.count
        var results: [DiscoveredResource] = []

        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            if values.isDirectory == true {
                if Self.skippedDirectories.contains(url.lastPathComponent) || isIgnored(url) {
                    walker.skipDescendants()
                }
                continue
            }

            guard results.count < maximumFilesPerRoot else { break }
            guard url.standardizedFileURL.pathComponents.count - rootDepth <= maximumDepth else { continue }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            // A near-empty file has nothing to summarise and would enter the
            // corpus as an orphan the janitor then has to flag.
            guard (values.fileSize ?? 0) >= minimumBytes else { continue }
            guard (values.fileSize ?? 0) <= maximumBytes else { continue }

            results.append(
                resource(at: url, under: root, modifiedAt: values.contentModificationDate ?? Date())
            )
        }
        return results
    }

    private func resource(at url: URL, under root: URL, modifiedAt: Date) -> DiscoveredResource {
        let parent = url.deletingLastPathComponent().lastPathComponent
        let title = ImporterText.sanitizeTitle("Doc: \(parent)/\(url.lastPathComponent)")

        var lines = [
            "**File:** `\(url.path)`",
            "**Modified:** \(ImporterText.dayFormatter.string(from: modifiedAt))"
        ]
        // The retrospective reads `**Project:**` and nothing else. Without this
        // line a folder of seventeen documents about one project enters the
        // corpus belonging to no project at all — the folder name is right
        // there in the path, and the only reason it went unread was that the
        // Claude-session pipeline happened to be the one that wrote the line
        // first. The *first* directory under the nominated root, not the file's
        // own parent, so `Nuptia/studio-notes/03.md` counts as Nuptia rather
        // than as a project called "studio-notes".
        if let project = projectDirectory(of: url, under: root) {
            lines.append("**Project:** `\(project.path)`")
        }
        if let excerpt = excerpt(of: url) {
            lines.append("")
            lines.append("**Opens with:**")
            lines.append("> " + excerpt)
        }

        return DiscoveredResource(
            sourceURL: url,
            // The path is this resource's identity: the file can be renamed in
            // content or edited freely, but it is the same document as long as
            // it is the same file.
            key: url.path,
            title: title,
            summary: lines.joined(separator: "\n"),
            tags: ["document", "ingested"],
            occurredAt: modifiedAt
        )
    }

    /// The folder immediately under `root` that this file sits in.
    ///
    /// `nil` for a file lying loose in the root itself: nominating
    /// `~/Documents` and indexing a stray `notes.md` should not invent a
    /// project called Documents, which is the same failure
    /// `Retrospective.project(of:)` guards against for home directories.
    private func projectDirectory(of url: URL, under root: URL) -> URL? {
        let rootParts = root.standardizedFileURL.pathComponents
        let fileParts = url.standardizedFileURL.pathComponents
        guard fileParts.count > rootParts.count + 1,
              Array(fileParts.prefix(rootParts.count)) == rootParts else { return nil }
        // `pathComponents` leads with "/" on an absolute path, so the slice is
        // one longer than the number of directories it names.
        let project = fileParts.prefix(rootParts.count + 1).dropFirst()
        return URL(fileURLWithPath: "/" + project.joined(separator: "/"))
    }

    /// Reads only the head of the file. The whole thing goes to `/raw`; the note
    /// needs just enough to tell someone whether this is the file they wanted.
    private func excerpt(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4096), let text = String(data: head, encoding: .utf8) else {
            return nil
        }
        let body = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Leading markdown headings and front-matter fences say nothing the
            // title doesn't already.
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0 != "---" }
            .joined(separator: " ")
        let condensed = ImporterText.condense(body, limit: 400)
        return condensed.isEmpty ? nil : condensed
    }

    /// Two roots can each hold a `docs/README.md`. Titles are permanent and
    /// resolve wiki-links by exact match, so a collision has to be broken here
    /// rather than left for the runner to skip — otherwise the second file would
    /// never be ingestable at all.
    private func disambiguate(_ resources: [DiscoveredResource]) -> [DiscoveredResource] {
        var counts: [String: Int] = [:]
        for resource in resources { counts[resource.title, default: 0] += 1 }

        return resources.map { resource in
            guard counts[resource.title, default: 0] > 1 else { return resource }
            // Derived from the full path, so it's stable across runs — the same
            // file gets the same title every time, which is what lets the runner
            // recognise it instead of creating a second note.
            //
            // SHA-256 rather than `hashValue`: Swift seeds `Hasher` randomly per
            // process, so a `hashValue`-derived suffix would differ on every
            // launch and each run would mint a *new* permanent title for the
            // same file — the exact duplicate-forever bug this method exists to
            // prevent.
            let suffix = ImporterText.stableSuffix(for: resource.sourceURL.path)
            return DiscoveredResource(
                sourceURL: resource.sourceURL,
                key: resource.key,
                title: "\(resource.title) (\(suffix))",
                summary: resource.summary,
                tags: resource.tags,
                occurredAt: resource.occurredAt
            )
        }
    }
}
