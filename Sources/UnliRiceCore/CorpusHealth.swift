import Foundation

/// Checks that the corpus the app just opened is the one the user meant.
///
/// This exists because of a failure that ran for a month without anyone
/// noticing: the default event-log location moved, the old log was left behind
/// with more notes in it than the new one, and nothing in the system was
/// capable of observing that. Every component behaved correctly in isolation.
/// The fault was only visible by comparing two files, and nothing compared them.
///
/// So: compare them. Cheaply, at launch, and say something when the comparison
/// looks wrong.
///
/// Deliberately read-only. It reports; it never adopts, merges, or switches. A
/// corpus is the user's data and choosing between two of them is a structural
/// decision, which this codebase proposes rather than applies (decision #3).
public enum CorpusHealth {
    public enum Finding: Equatable, Sendable {
        /// The user chose a folder and the app could not open it, so it is
        /// running on the default corpus instead.
        case chosenFolderUnavailable(CorpusLocation.FolderFailure)

        /// A log at a location this app used to default to holds notes that
        /// are not in the one now open. Either a relocation left data behind,
        /// or two corpora have diverged.
        case strandedCorpus(path: String, missingNotes: Int)
    }

    /// - Parameters:
    ///   - location: what `CorpusLocation.resolve` returned.
    ///   - candidates: previous default locations to compare against.
    ///   - noteIDs: injected so this is testable without real logs.
    public static func check(
        location: CorpusLocation,
        candidates: [URL] = DataLocation.predecessorEventLogURLs(),
        noteIDs: (URL) -> Set<String>? = DataLocation.createdNoteIDs(inLogAt:)
    ) -> [Finding] {
        var findings: [Finding] = []

        if case .defaultAfterFolderFailed(let failure) = location.source {
            findings.append(.chosenFolderUnavailable(failure))
        }

        // Only meaningful for the default corpus. A folder the user picked on
        // purpose is *supposed* to differ from whatever is in the app's own
        // directory, and nagging about that would train the alert away.
        guard location.isDefaultLocation else { return findings }

        // Identity, not size. A log that has merely fallen behind is fine; a
        // log holding notes the open one has never seen is data left behind.
        let openIDs = noteIDs(location.url) ?? []
        let stranded = candidates
            .filter { $0.standardizedFileURL != location.url.standardizedFileURL }
            .compactMap { url -> (String, Int)? in
                guard let ids = noteIDs(url) else { return nil }
                let missing = ids.subtracting(openIDs).count
                guard missing > 0 else { return nil }
                return (url.deletingLastPathComponent().path, missing)
            }
            .max { $0.1 < $1.1 }

        if let (path, missing) = stranded {
            findings.append(.strandedCorpus(path: path, missingNotes: missing))
        }
        return findings
    }

    /// The user-facing form. One notice per finding.
    public static func notices(for findings: [Finding]) -> [Notice] {
        findings.map { finding in
            switch finding {
            case .chosenFolderUnavailable(let failure):
                return NoticeFactory.notesFolderUnavailable(failure)
            case .strandedCorpus(let path, let missing):
                return NoticeFactory.strandedCorpus(path: path, missingNotes: missing)
            }
        }
    }
}
