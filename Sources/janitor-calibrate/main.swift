import Foundation
import UnliRiceCore
import UnliRiceMLX

/// Dry-runs the janitor's rules over a real corpus and reports what each
/// similarity engine would surface, without writing anything anywhere.
///
/// This exists because the duplicate thresholds are not guessable. Token
/// overlap and embedding cosine both return 0...1 and the numbers mean entirely
/// different things — the only way to know where the line goes is to look at
/// the score distribution over real titles. It's kept in the repo rather than
/// thrown away because the answer changes as the corpus grows.
///
/// Read-only by construction: it opens a *copy* of the log and calls only
/// `preview`, never `run`.
///
///     swift run janitor-calibrate [path-to-events.jsonl]

let arguments = CommandLine.arguments
let sourcePath = arguments.count > 1
    ? arguments[1]
    : DataLocation.defaultEventLogURL().path

guard FileManager.default.fileExists(atPath: sourcePath) else {
    print("No event log at \(sourcePath)")
    exit(1)
}

// Work on a copy. `preview` writes nothing, but the whole point of this tool is
// to be trustworthy about not touching real notes, and a copy makes that true
// by construction rather than by reading the call graph.
let workingCopy = FileManager.default.temporaryDirectory
    .appendingPathComponent("unlirice-calibrate-\(UUID().uuidString).jsonl")
try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: workingCopy)
defer { try? FileManager.default.removeItem(at: workingCopy) }

let service = NoteService(store: try EventStore(fileURL: workingCopy))
let notes = try service.listNotes(includeArchived: false)
let titles = notes.map(\.title)

print("corpus: \(notes.count) live notes from \(sourcePath)")
print("(working on a copy — the real log is not opened for writing)\n")

// MARK: - Score distributions

func pairScores(_ provider: SimilarityProvider) -> [(Double, String, String)] {
    var scores: [(Double, String, String)] = []
    for (index, a) in titles.enumerated() {
        for b in titles.dropFirst(index + 1) {
            scores.append((provider.similarity(a, b), a, b))
        }
    }
    return scores.sorted { $0.0 > $1.0 }
}

func report(_ name: String, _ provider: SimilarityProvider) {
    let scores = pairScores(provider)
    let values = scores.map(\.0).sorted()
    func percentile(_ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        return values[min(values.count - 1, Int(Double(values.count - 1) * p))]
    }

    print("=== \(name) ===")
    print(String(
        format: "%d pairs | median %.3f | p90 %.3f | p99 %.3f | max %.3f",
        scores.count, percentile(0.5), percentile(0.9), percentile(0.99), values.last ?? 0
    ))
    print(String(
        format: "thresholds in use: default %.2f, aggressive %.2f",
        provider.calibration.duplicateThreshold,
        provider.calibration.aggressiveDuplicateThreshold
    ))
    // The number that actually decides a threshold: how many pairs clear it.
    // A threshold is only good if the pairs above it are the ones a human would
    // also call duplicates, and the count is small enough to be read.
    print("pairs above:")
    let candidates = (Array(stride(from: 0.5, through: 0.95, by: 0.05)) + [0.96, 0.97, 0.98, 0.985, 0.99]).sorted()
    for candidate in candidates {
        let above = scores.filter { $0.0 >= candidate }.count
        print(String(format: "  >= %.3f : %4d pairs", candidate, above))
    }
    print("top 10 pairs:")
    for (score, a, b) in scores.prefix(10) {
        print(String(format: "  %.3f  %@  ⟷  %@", score, a, b))
    }

    for autonomy in JanitorAutonomy.allCases {
        let proposals = Janitor.scan(
            notes: notes,
            config: JanitorConfig(autonomy: autonomy),
            similarity: provider
        )
        let cosmetic = proposals.filter { $0.risk == .cosmetic }.count
        let structural = proposals.count - cosmetic
        print("  \(autonomy): \(proposals.count) proposals (\(cosmetic) cosmetic, \(structural) would queue)")
    }
    print("")
}

report("token overlap (no model)", TokenOverlapSimilarity())

let mlx = try await MLXSimilarity.load { fraction in
    if fraction >= 1 { print("model ready") }
}
await mlx.warm(titles)
report("MLX embeddings (bge-micro)", mlx)
