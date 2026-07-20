import XCTest
@testable import UnliRiceCore

final class RemoteSimilarityTests: XCTestCase {
    /// The load-bearing test for this type. `warm(_:)` sends every note title to
    /// the endpoint, so a non-local address would be exfiltrating the user's own
    /// content because a URL was typed into a settings field.
    func testRefusesAnyEndpointThatIsNotLoopback() {
        for host in ["https://api.example.com/v1", "http://192.168.1.50:1234/v1", "http://evil.test/v1"] {
            XCTAssertThrowsError(
                try RemoteSimilarity(baseURL: URL(string: host)!, model: "m"),
                "accepted a non-loopback endpoint: \(host)"
            )
        }
    }

    func testAcceptsLoopbackAddresses() throws {
        for host in ["http://localhost:1234/v1", "http://127.0.0.1:11434/v1"] {
            XCTAssertNoThrow(try RemoteSimilarity(baseURL: URL(string: host)!, model: "m"), host)
        }
    }

    /// A cache miss must not be dressed up as a judgement — answering "0.0, not
    /// similar" for a title that was never embedded would silently suppress real
    /// duplicates. It falls back to token overlap instead.
    func testUnwarmedTitlesFallBackToTokenOverlapRatherThanZero() throws {
        let remote = try RemoteSimilarity(baseURL: URL(string: "http://localhost:1234/v1")!, model: "m")
        let overlap = TokenOverlapSimilarity()

        let a = "MCP server registration"
        let b = "MCP server registration notes"
        XCTAssertEqual(remote.similarity(a, b), overlap.similarity(a, b))
        XCTAssertGreaterThan(remote.similarity(a, b), 0)
    }

    func testCosineIsCorrect() {
        XCTAssertEqual(RemoteSimilarity.cosine([1, 0], [1, 0]), 1.0, accuracy: 0.0001)
        XCTAssertEqual(RemoteSimilarity.cosine([1, 0], [0, 1]), 0.0, accuracy: 0.0001)
        // Mismatched dimensions and zero vectors are answered 0 rather than
        // crashing or producing NaN.
        XCTAssertEqual(RemoteSimilarity.cosine([1, 0, 0], [1, 0]), 0)
        XCTAssertEqual(RemoteSimilarity.cosine([0, 0], [0, 0]), 0)
    }

    /// Thresholds travel with the provider — the lesson the removed MLX work
    /// paid for. An embedding scale and a Jaccard scale mean nothing alike.
    func testCalibrationDiffersFromTokenOverlap() throws {
        let remote = try RemoteSimilarity(baseURL: URL(string: "http://localhost:1234/v1")!, model: "m")
        XCTAssertNotEqual(
            remote.calibration.duplicateThreshold,
            SimilarityCalibration.tokenOverlap.duplicateThreshold
        )
    }
}

final class SimilarityCalibrationTests: XCTestCase {
    /// The retuned number, and the measurement behind it: over a 233-note
    /// post-ingest corpus, 0.75 queued 21 pairs where 0.85 queues 3 — and the
    /// difference was all false positives of the same kind (different files
    /// sharing a path prefix). See PROJECT_NOTES.md.
    func testTokenOverlapDuplicateThresholdIsTheMeasuredOne() {
        XCTAssertEqual(SimilarityCalibration.tokenOverlap.duplicateThreshold, 0.85)
    }

    /// Aggressive must stay looser than the default or the slider's middle
    /// setting would surface more than its loudest one.
    func testAggressiveIsLooserThanDefault() {
        let calibration = SimilarityCalibration.tokenOverlap
        XCTAssertLessThan(calibration.aggressiveDuplicateThreshold, calibration.duplicateThreshold)
    }
}
