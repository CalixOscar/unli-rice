import Foundation

public enum BuildGate {
    public enum Stage: String, CaseIterable, Hashable, Sendable { case idea, intent, spec, agents, premortem, build, postmortem }
    public enum Light: Equatable, Sendable { case done, draft(String), skipped(String), notRequired(String), notRecorded, missing, unknown(String) }
    public struct Result: Equatable, Sendable {
        public let slug: String?; public let openPlans: [String]; public let lights: [Stage: Light]; public let issues: [String]
        public init(slug: String?, openPlans: [String], lights: [Stage: Light], issues: [String]) { self.slug = slug; self.openPlans = openPlans; self.lights = lights; self.issues = issues }
    }

    private enum ReadResult { case text(String), missing, failure(String) }
    private struct HeaderFile { let values: [String: String]; func value(_ name: String) -> String? { values[name] } }
    private struct Turn { let author: String; let kind: String }
    private struct Dialogue { let planner: String?; let reviewer: String?; let state: String?; let turns: [Turn] }
    private static let maxFileSize = 128 * 1024
    private static let stagePattern = try! NSRegularExpression(pattern: #"^\*\*Stage:\*\* (\d+)"#)
    private static let pathPattern = try! NSRegularExpression(pattern: #"docs/[A-Za-z0-9._/-]+\.md"#)
    private static let turnPattern = try! NSRegularExpression(pattern: #"^## ([a-z]+) — (pre-mortem|response|settled|post-mortem|rebuttal) — (\d{4}-\d{2}-\d{2})\s*$"#)

    public static func current(folder: URL) -> Result {
        let root = folder.standardizedFileURL, docs = root.appendingPathComponent("docs", isDirectory: true)
        let entries: [URL]
        do { entries = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) }
        catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile { return noPlanResult(folder: root) }
        catch { return unknownResult(slug: nil, reason: "could not read docs/") }
        guard entries.count <= 500 else { return unknownResult(slug: nil, reason: "too many files in docs/") }
        let plans = entries.compactMap { url -> (slug: String, date: Date, stage: Int?)? in
            let name = url.lastPathComponent
            guard name.hasPrefix("PLAN-"), name.hasSuffix(".md") else { return nil }
            let slug = String(name.dropFirst(5).dropLast(3)); guard !slug.isEmpty else { return nil }
            let stage: Int?; if case let .text(text) = read(url: url, root: root) { stage = firstStage(in: text) } else { stage = nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (slug, date, stage)
        }
        let open = plans.filter { $0.stage != nil && $0.stage! <= 4 }; guard !open.isEmpty else { return noPlanResult(folder: root) }
        let chosen = open.sorted { $0.date != $1.date ? $0.date > $1.date : $0.slug.localizedCaseInsensitiveCompare($1.slug) == .orderedAscending }.first!
        let openSlugs = open.map(\.slug).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let result = read(folder: root, slug: chosen.slug); var issues = result.issues
        let others = openSlugs.filter { $0 != chosen.slug }; if !others.isEmpty { issues.append("\(others.count) other open plans: \(others.joined(separator: ", "))") }
        return Result(slug: result.slug, openPlans: openSlugs, lights: result.lights, issues: issues)
    }

    public static func read(folder: URL, slug: String) -> Result {
        let root = folder.standardizedFileURL, planURL = root.appendingPathComponent("docs/PLAN-\(slug).md")
        guard case let .text(plan) = read(url: planURL, root: root) else { return unknownResult(slug: slug, reason: "could not read plan") }
        var lights = emptyLights(), issues: [String] = []; let planHeaders = headers(in: plan)
        let intent = extractedPath(value: planHeaders.value("Intent"), name: "Intent")
        lights[.intent] = evidenceLight(path: intent.path, noPathLight: intent.noPath, root: root)
        if let specValue = planHeaders.value("Spec") { let spec = extractedPath(value: specValue, name: "Spec"); lights[.spec] = specLight(path: spec.path, noPathLight: spec.noPath, intentPath: intent.path, root: root) }
        else { lights[.spec] = .notRequired("older plan") }
        lights[.agents] = agentsLight(root: root, issues: &issues)
        lights[.idea] = ideaLight(planHeaders: planHeaders, slug: slug, root: root)
        lights[.premortem] = preMortemLight(planHeaders: planHeaders, slug: slug, root: root, issues: &issues)
        lights[.build] = buildLight(plan: plan); lights[.postmortem] = postMortemLight(slug: slug, root: root)
        return Result(slug: slug, openPlans: [], lights: lights, issues: issues)
    }

    private static func emptyLights() -> [Stage: Light] { Dictionary(uniqueKeysWithValues: Stage.allCases.map { ($0, .unknown("not evaluated")) }) }
    private static func noPlanResult(folder: URL) -> Result { var lights = emptyLights(), issues: [String] = []; lights[.agents] = agentsLight(root: folder, issues: &issues); for stage in Stage.allCases where stage != .agents { lights[stage] = .notRecorded }; return Result(slug: nil, openPlans: [], lights: lights, issues: issues) }
    private static func unknownResult(slug: String?, reason: String) -> Result { Result(slug: slug, openPlans: [], lights: Dictionary(uniqueKeysWithValues: Stage.allCases.map { ($0, .unknown(reason)) }), issues: []) }

    private static func extractedPath(value: String?, name: String) -> (path: String?, noPath: Light?) {
        guard let value else { return (nil, nil) }; let range = NSRange(value.startIndex..., in: value)
        if let match = pathPattern.firstMatch(in: value, range: range), let r = Range(match.range, in: value) { return (String(value[r]), nil) }
        let lower = value.lowercased(); if lower.hasPrefix("none") || lower.hasPrefix("no ") { return (nil, .notRequired(String(value.prefix(80)))) }
        return (nil, .unknown("no path on the \(name) line"))
    }
    private static func evidenceLight(path: String?, noPathLight: Light?, root: URL) -> Light {
        guard let path else { return noPathLight ?? .missing }
        switch read(url: root.appendingPathComponent(path), root: root) { case .text(let text): let status = headers(in: text).value("Status") ?? "not approved yet"; return startsApproved(status) ? .done : .draft("not approved yet"); case .missing: return .missing; case .failure(let reason): return .unknown(reason) }
    }
    private static func specLight(path: String?, noPathLight: Light?, intentPath: String?, root: URL) -> Light {
        guard let path else { return noPathLight ?? .unknown("no path on the Spec line") }
        switch read(url: root.appendingPathComponent(path), root: root) {
        case .text(let text): let file = headers(in: text); guard let named = file.value("Intent"), firstPath(in: named) == intentPath else { return .unknown("spec names a different intent") }; let status = file.value("Status") ?? "not approved yet"; return startsApproved(status) ? .done : .draft(status)
        case .missing: return .missing
        case .failure(let reason): return .unknown(reason)
        }
    }
    private static func agentsLight(root: URL, issues: inout [String]) -> Light {
        switch read(url: root.appendingPathComponent("AGENTS.md"), root: root) {
        case .missing: return .missing; case .failure(let reason): return .unknown(reason); case .text:
            switch read(url: root.appendingPathComponent("CLAUDE.md"), root: root) { case .missing: return .done; case .failure(let reason): return .unknown(reason); case .text(let text): let imports = text.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "@AGENTS.md" }; if imports { return .done }; let reason = "CLAUDE.md doesn't import AGENTS.md"; issues.append(reason); return .draft(reason) }
        }
    }
    private static func ideaLight(planHeaders: HeaderFile, slug: String, root: URL) -> Light {
        switch read(url: root.appendingPathComponent("docs/idea/IDEA-\(slug).md"), root: root) { case .text: return .done; case .failure(let reason): return .unknown(reason); case .missing: break }
        guard let value = planHeaders.value("Idea") else { return .notRecorded }; let lower = value.lowercased(); if lower.hasPrefix("not needed") { return .notRequired(skipQuote(value)) }; if lower.hasPrefix("skipped") { return .skipped(skipQuote(value)) }; return .notRecorded
    }
    private static func preMortemLight(planHeaders: HeaderFile, slug: String, root: URL, issues: inout [String]) -> Light {
        if let declaration = planHeaders.value("Pre-mortem"), declaration.lowercased().hasPrefix("skipped") { return .skipped(skipQuote(declaration)) }
        switch read(url: root.appendingPathComponent("docs/dialogue/\(slug).md"), root: root) { case .missing: return .missing; case .failure(let reason): return .unknown(reason); case .text(let text): let parsed = dialogue(text, issues: &issues); guard let planner = parsed.planner, let reviewer = parsed.reviewer else { return .unknown("dialogue header has no planner or reviewer") }; guard planner != reviewer else { return .unknown("reviewer and planner are the same tool") }; guard let review = parsed.turns.lastIndex(where: { ($0.kind == "pre-mortem" || $0.kind == "rebuttal") && $0.author == reviewer }) else { return .missing }; guard let settled = parsed.turns.lastIndex(where: { $0.kind == "settled" && $0.author == planner }) else { return .draft("waiting for the planner to settle") }; return ["settled", "built", "closed"].contains(parsed.state ?? "") && settled > review ? .done : .draft("waiting for the planner to settle") }
    }
    private static func postMortemLight(slug: String, root: URL) -> Light {
        switch read(url: root.appendingPathComponent("docs/dialogue/\(slug).md"), root: root) { case .missing: return .missing; case .failure(let reason): return .unknown(reason); case .text(let text): var issues: [String] = []; let parsed = dialogue(text, issues: &issues); guard let planner = parsed.planner, let reviewer = parsed.reviewer, planner != reviewer, let settled = parsed.turns.lastIndex(where: { $0.kind == "settled" && $0.author == planner }) else { return .missing }; return parsed.turns.enumerated().contains { $0.offset > settled && $0.element.kind == "post-mortem" && $0.element.author == reviewer } ? .done : .missing }
    }
    private static func buildLight(plan: String) -> Light { guard let stage = firstStage(in: plan) else { return .unknown("plan stage has no number") }; return stage >= 5 ? .done : .missing }

    /// Physical lines, blank ones included, so "the first 40 lines" means what a reader sees.
    private static func physicalLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    /// §2.6 "Reading header lines": the first 40 physical lines only, fenced lines skipped,
    /// and the first occurrence of a name wins.
    private static func headers(in text: String) -> HeaderFile {
        var values: [String: String] = [:], fenced = false
        for raw in physicalLines(text).prefix(40) {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
            guard !fenced, raw.hasPrefix("**"), let end = raw.range(of: ":**") else { continue }
            let name = String(raw[raw.index(raw.startIndex, offsetBy: 2)..<end.lowerBound])
            guard values[name] == nil else { continue }
            values[name] = String(raw[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return HeaderFile(values: values)
    }

    /// Header fields come from `headers(in:)`; turns are read from the whole file in line
    /// order, skipping fenced lines. Line numbers in issues are physical line numbers.
    private static func dialogue(_ text: String, issues: inout [String]) -> Dialogue {
        let header = headers(in: text)
        let planner = header.value("Planner").map(firstWord).flatMap { $0.isEmpty ? nil : $0 }
        let reviewer = header.value("Reviewer").map(firstWord).flatMap { $0.isEmpty ? nil : $0 }
        let state = header.value("State").map(firstWord)
        var turns: [Turn] = [], fenced = false
        for (index, line) in physicalLines(text).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
            guard !fenced else { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = turnPattern.firstMatch(in: line, range: range) else { continue }
            let author = String(line[Range(match.range(at: 1), in: line)!])
            let kind = String(line[Range(match.range(at: 2), in: line)!])
            if let planner, let reviewer, author != planner, author != reviewer {
                issues.append("dialogue turn by \(author) on line \(index + 1) ignored: not the planner or reviewer")
                continue
            }
            turns.append(Turn(author: author, kind: kind))
        }
        return Dialogue(planner: planner, reviewer: reviewer, state: state, turns: turns)
    }
    private static func firstWord(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() } ?? "" }
    private static func firstPath(in value: String) -> String? { let range = NSRange(value.startIndex..., in: value); guard let match = pathPattern.firstMatch(in: value, range: range), let r = Range(match.range, in: value) else { return nil }; return String(value[r]) }
    private static func skipQuote(_ value: String) -> String { value.drop { $0 != "—" && $0 != "-" }.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func startsApproved(_ value: String) -> Bool { value.lowercased().hasPrefix("approved") }
    /// The stage number is read from the bounded header block like every other header line.
    private static func firstStage(in text: String) -> Int? {
        guard let value = headers(in: text).value("Stage") else { return nil }
        let line = "**Stage:** " + value, range = NSRange(line.startIndex..., in: line)
        guard let match = stagePattern.firstMatch(in: line, range: range),
              let numberRange = Range(match.range(at: 1), in: line) else { return nil }
        return Int(line[numberRange])
    }
    private static func read(url: URL, root: URL) -> ReadResult {
        guard isSafe(url: url, root: root) else { return .failure("path resolves outside folder") }; guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do { let attrs = try FileManager.default.attributesOfItem(atPath: url.path); guard let size = attrs[.size] as? NSNumber, size.intValue <= maxFileSize else { return .failure("file too large to check") }; let data = try Data(contentsOf: url); guard data.count <= maxFileSize else { return .failure("file too large to check") }; guard let text = String(data: data, encoding: .utf8) else { return .failure("could not read file") }; return .text(text) } catch { return .failure("could not read file") }
    }
    private static func isSafe(url: URL, root: URL) -> Bool { let plain = url.standardizedFileURL.path, resolved = url.resolvingSymlinksInPath().standardizedFileURL.path, rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"; return (plain == root.path || plain.hasPrefix(rootPath)) && (resolved == root.path || resolved.hasPrefix(rootPath)) && plain == resolved }
}
