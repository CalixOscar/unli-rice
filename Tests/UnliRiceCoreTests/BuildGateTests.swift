import Foundation
import XCTest
@testable import UnliRiceCore

final class BuildGateTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("build-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try write("rules", to: "AGENTS.md")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testFeatureBindingIgnoresOtherFeaturesFiles() throws {
        try plan("one", stage: 4, intent: "docs/intent/INTENT-one.md")
        try write("**Status:** approved\n", to: "docs/intent/INTENT-other.md")
        XCTAssertEqual(BuildGate.current(folder: root).slug, "one")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "one").lights[.intent], .missing)
    }

    func testTwoOpenPlansPicksNewestButListsBoth() throws {
        try plan("old", stage: 4); try plan("new", stage: 4)
        let old = root.appendingPathComponent("docs/PLAN-old.md")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: old.path)
        let result = BuildGate.current(folder: root)
        XCTAssertEqual(result.slug, "new"); XCTAssertEqual(result.openPlans, ["new", "old"])
    }

    func testCopiedTimestampDoesNotChangeEvidence() throws {
        try plan("x", stage: 4, intent: "docs/intent/X.md")
        try write("**Status:** approved\n", to: "docs/intent/X.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.intent], .done)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: root.appendingPathComponent("docs/intent/X.md").path)
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.intent], .done)
    }

    func testDraftSpecIsDraft() throws {
        try plan("x", stage: 4, intent: "docs/intent/X.md", spec: "docs/SPEC-x.md")
        try write("**Status:** draft\n**Intent:** docs/intent/X.md\n", to: "docs/SPEC-x.md")
        if case .draft("draft") = BuildGate.read(folder: root, slug: "x").lights[.spec] {} else { XCTFail() }
    }

    func testSpecNamingOtherIntentIsUnknown() throws {
        try plan("x", stage: 4, intent: "docs/intent/X.md", spec: "docs/SPEC-x.md")
        try write("**Status:** approved\n**Intent:** docs/intent/other.md\n", to: "docs/SPEC-x.md")
        if case .unknown("spec names a different intent") = BuildGate.read(folder: root, slug: "x").lights[.spec] {} else { XCTFail() }
    }

    func testLegacyPlanSpecNotRequired() throws {
        try plan("x", stage: 4)
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.spec], .notRequired("older plan"))
    }

    func testSettledByWrongAuthorIsNotDone() throws {
        try plan("x", stage: 4); try dialogue("x", settledBy: "codex", premortemBy: "codex")
        XCTAssertNotEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .done)
    }

    func testSettledBeforeLastPremortemIsNotDone() throws {
        try plan("x", stage: 4); try dialogue("x", settledBy: "claude", premortemBy: "codex", lateReview: true)
        XCTAssertNotEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .done)
    }

    func testHeadingInsideCodeFenceIgnored() throws {
        try plan("x", stage: 4); try write("**Planner:** claude\n**Reviewer:** codex\n**State:** settled\n```\n## codex — pre-mortem — 2026-10-01\n```\n## claude — settled — 2026-10-02\n", to: "docs/dialogue/x.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .missing)
    }

    func testSameToolBothRolesUnknown() throws {
        try plan("x", stage: 4); try write("**Planner:** claude\n**Reviewer:** claude\n", to: "docs/dialogue/x.md")
        if case .unknown = BuildGate.read(folder: root, slug: "x").lights[.premortem] {} else { XCTFail() }
    }

    func testPremortemSkipRecorded() throws {
        try plan("x", stage: 4, premortem: "skipped — founder chose speed")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .skipped("founder chose speed"))
    }

    func testIdeaNotRecordedByDefault() throws { try plan("x", stage: 4); XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.idea], .notRecorded) }
    func testIdeaNotRequiredLine() throws { try plan("x", stage: 4, idea: "not needed — existing app"); XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.idea], .notRequired("existing app")) }
    func testClaudeMdWithoutImportIsDraft() throws { try plan("x", stage: 4); try write("rules", to: "CLAUDE.md"); XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.agents], .draft("CLAUDE.md doesn't import AGENTS.md")) }
    func testUnreadableFolderIsUnknownNotMissing() throws { try plan("x", stage: 4); try FileManager.default.removeItem(at: root.appendingPathComponent("docs/PLAN-x.md")); try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/PLAN-x.md"), withIntermediateDirectories: true); if case .unknown = BuildGate.read(folder: root, slug: "x").lights[.intent] {} else { XCTFail() } }
    func testOversizeFileUnknown() throws { try plan("x", stage: 4, intent: "docs/intent/X.md"); try write(String(repeating: "x", count: 129 * 1024), to: "docs/intent/X.md"); if case .unknown = BuildGate.read(folder: root, slug: "x").lights[.intent] {} else { XCTFail() } }
    func testDocsOver500EntriesUnknown() throws { for i in 0..<501 { try write("x", to: "docs/file-\(i).md") }; if case .unknown = BuildGate.current(folder: root).lights[.idea] {} else { XCTFail() } }
    func testSymlinkOutsideFolderUnknown() throws { let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)"); try write("**Status:** approved", absolute: outside); try plan("x", stage: 4, intent: "docs/intent/X.md"); try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs/intent/X.md"), withDestinationURL: outside); if case .unknown = BuildGate.read(folder: root, slug: "x").lights[.intent] {} else { XCTFail() }; try? FileManager.default.removeItem(at: outside) }
    func testReadsNothingOutsideDocsAndRoot() throws { try plan("x", stage: 4); XCTAssertEqual(BuildGate.current(folder: root).slug, "x") }
    func testUnknownAuthorAddsIssue() throws { try plan("x", stage: 4); try write("**Planner:** claude\n**Reviewer:** codex\n**State:** settled\n## gemini — response — 2026-10-01\n", to: "docs/dialogue/x.md"); XCTAssertTrue(BuildGate.read(folder: root, slug: "x").issues.contains { $0.contains("gemini") }) }
    func testNoPlanGivesNotRecorded() throws { let result = BuildGate.current(folder: root); XCTAssertEqual(result.slug, nil); XCTAssertEqual(result.lights[.idea], .notRecorded) }
    func testNoDocsFolderGivesNotRecorded() throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent("docs"))
        let result = BuildGate.current(folder: root)
        XCTAssertEqual(result.slug, nil); XCTAssertEqual(result.lights[.idea], .notRecorded)
    }
    func testStageNumberDecidesBuild() throws { try plan("x", stage: 5); XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.build], .done) }
    func testNotBuiltWordingIsNotDone() throws { try plan("x", stage: 4); XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.build], .missing) }
    func testSameDayRebuttalAfterSettledIsDraft() throws {
        try plan("x", stage: 4)
        try write("**Planner:** claude\n**Reviewer:** codex\n**State:** settled\n## codex — pre-mortem — 2026-10-01\n## claude — settled — 2026-10-01\n## codex — rebuttal — 2026-10-01\n", to: "docs/dialogue/x.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .draft("waiting for the planner to settle"))
    }

    func testSameDayPostmortemAfterSettledIsDone() throws {
        try plan("x", stage: 4)
        try write("**Planner:** claude\n**Reviewer:** codex\n**State:** built\n## codex — pre-mortem — 2026-10-01\n## claude — settled — 2026-10-01\n## codex — post-mortem — 2026-10-01\n", to: "docs/dialogue/x.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.postmortem], .done)
    }

    func testTurnOrderIgnoresDates() throws {
        try plan("x", stage: 4)
        try write("**Planner:** claude\n**Reviewer:** codex\n**State:** settled\n## codex — pre-mortem — 2026-10-02\n## claude — settled — 2026-10-01\n", to: "docs/dialogue/x.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .done)
    }

    func testBacktickedPathWithTrailingTextResolves() throws {
        try plan("x", stage: 4, intent: "`docs/intent/X.md` (approved by founder)")
        try write("**Status:** approved\n", to: "docs/intent/X.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.intent], .done)
    }

    func testBarePathResolves() throws {
        try plan("x", stage: 4, intent: "docs/intent/X.md")
        try write("**Status:** approved\n", to: "docs/intent/X.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.intent], .done)
    }

    func testIntentNoneIsNotRequired() throws {
        try plan("x", stage: 4, intent: "none. This comes from an older plan")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.intent], .notRequired("none. This comes from an older plan"))
    }

    func testIntentLineWithoutPathIsUnknown() throws {
        try plan("x", stage: 4, intent: "approved by founder")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.intent], .unknown("no path on the Intent line"))
    }

    func testHeaderSearchStopsAt40Lines() throws {
        // 40 physical lines, half of them blank: a header on line 41 is out of bounds.
        var body = (0..<40).map { $0 % 2 == 0 ? "" : "line \($0)" }.joined(separator: "\n")
        body += "\n**Intent:** docs/intent/X.md\n**Stage:** 4\n"
        try write(body, to: "docs/PLAN-x.md")
        try write("**Status:** approved\n", to: "docs/intent/X.md")
        let result = BuildGate.read(folder: root, slug: "x")
        XCTAssertEqual(result.lights[.intent], .missing)
        XCTAssertEqual(result.lights[.build], .unknown("plan stage has no number"))
    }

    func testFirstHeaderWins() throws {
        try write("**Stage:** 4\n**Intent:** docs/intent/X.md\n**Intent:** docs/intent/Y.md\n", to: "docs/PLAN-x.md")
        try write("**Status:** approved\n", to: "docs/intent/X.md")
        try write("**Status:** draft\n", to: "docs/intent/Y.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.intent], .done)
    }

    func testDialogueHeaderBeyond40LinesIsIgnored() throws {
        try plan("x", stage: 4)
        let padding = Array(repeating: "", count: 40).joined(separator: "\n")
        try write(padding + "\n**Planner:** claude\n**Reviewer:** codex\n**State:** settled\n## codex — pre-mortem — 2026-10-01\n## claude — settled — 2026-10-01\n", to: "docs/dialogue/x.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .unknown("dialogue header has no planner or reviewer"))
    }

    func testStateWithTrailingNoteCountsAsSettled() throws {
        try plan("x", stage: 4)
        try write("**Planner:** claude\n**Reviewer:** codex\n**State:** settled (2026-10-30)\n## codex — pre-mortem — 2026-10-01\n## claude — settled — 2026-10-01\n", to: "docs/dialogue/x.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "x").lights[.premortem], .done)
    }

    func testRealHeaderFormatsFromThisRepo() throws {
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func line(_ path: String, startsWith prefix: String) throws -> String {
            let text = try String(contentsOf: checkout.appendingPathComponent(path), encoding: .utf8)
            guard let found = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(prefix) }) else { throw NSError(domain: "BuildGateTests", code: 1) }
            return String(found)
        }
        let studioPlan = try [
            line("docs/PLAN-studio-redesign.md", startsWith: "**Intent:**"),
            line("docs/PLAN-studio-redesign.md", startsWith: "**Spec:**"),
            line("docs/PLAN-studio-redesign.md", startsWith: "**Stage:")
        ].joined(separator: "\n") + "\n"
        try write(studioPlan, to: "docs/PLAN-studio-redesign.md")
        try write(try line("docs/SPEC-studio-redesign.md", startsWith: "**Intent:") + "\n" + line("docs/SPEC-studio-redesign.md", startsWith: "**Status:") + "\n", to: "docs/SPEC-studio-redesign.md")
        try write(try line("docs/intent/INTENT-009-studio-redesign.md", startsWith: "**Status:") + "\n", to: "docs/intent/INTENT-009-studio-redesign.md")
        var result = BuildGate.current(folder: root)
        XCTAssertEqual(result.slug, "studio-redesign")
        XCTAssertEqual(result.lights[.intent], .done); XCTAssertEqual(result.lights[.spec], .done); XCTAssertEqual(result.lights[.build], .missing)

        let fourJobs = try [line("docs/PLAN-four-jobs.md", startsWith: "**Intent:"), line("docs/PLAN-four-jobs.md", startsWith: "**Stage:")].joined(separator: "\n") + "\n"
        try write(fourJobs, to: "docs/PLAN-four-jobs.md")
        try write(try line("docs/intent/INTENT-006-four-jobs.md", startsWith: "**Status:") + "\n", to: "docs/intent/INTENT-006-four-jobs.md")
        let fourResult = BuildGate.read(folder: root, slug: "four-jobs")
        XCTAssertEqual(fourResult.lights[.intent], .done); XCTAssertEqual(fourResult.lights[.spec], .notRequired("older plan")); XCTAssertEqual(fourResult.lights[.build], .done)
        XCTAssertFalse(BuildGate.current(folder: root).openPlans.contains("four-jobs"))
        XCTAssertTrue(BuildGate.current(folder: root).openPlans.contains("studio-redesign"))

        try write(try line("docs/PLAN-bridge-hardening.md", startsWith: "**Intent:") + "\n", to: "docs/PLAN-bridge-hardening.md")
        XCTAssertEqual(BuildGate.read(folder: root, slug: "bridge-hardening").lights[.intent], .notRequired("none. This comes from Codex's post-mortem of"))

        try write(try line("docs/PLAN-cleanup-menu-toast.md", startsWith: "**Stage:") + "\n", to: "docs/PLAN-cleanup-menu-toast.md")
        result = BuildGate.current(folder: root)
        XCTAssertFalse(result.openPlans.contains("cleanup-menu-toast"))
        XCTAssertEqual(BuildGate.read(folder: root, slug: "cleanup-menu-toast").lights[.intent], .missing)
        XCTAssertEqual(BuildGate.read(folder: root, slug: "cleanup-menu-toast").lights[.build], .unknown("plan stage has no number"))
    }

    private func plan(_ slug: String, stage: Int, intent: String? = nil, spec: String? = nil, idea: String? = nil, premortem: String? = nil) throws {
        var body = "**Stage:** \(stage)\n"
        if let intent { body += "**Intent:** \(intent)\n" }
        if let spec { body += "**Spec:** \(spec)\n" }
        if let idea { body += "**Idea:** \(idea)\n" }
        if let premortem { body += "**Pre-mortem:** \(premortem)\n" }
        try write(body, to: "docs/PLAN-\(slug).md")
        for path in ["docs/intent", "docs/dialogue"] { try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true) }
    }

    private func dialogue(_ slug: String, settledBy: String, premortemBy: String, lateReview: Bool = false) throws {
        var body = "**Planner:** claude\n**Reviewer:** codex\n**State:** settled\n## \(premortemBy) — pre-mortem — 2026-10-01\n## claude — settled — 2026-10-02\n"
        if lateReview { body += "## codex — rebuttal — 2026-10-03\n" }
        if settledBy != "claude" { body = body.replacingOccurrences(of: "## claude — settled", with: "## \(settledBy) — settled") }
        try write(body, to: "docs/dialogue/\(slug).md")
    }

    private func write(_ value: String, to relative: String) throws { try write(value, absolute: root.appendingPathComponent(relative)) }
    private func write(_ value: String, absolute: URL) throws { try FileManager.default.createDirectory(at: absolute.deletingLastPathComponent(), withIntermediateDirectories: true); try Data(value.utf8).write(to: absolute) }
}
