import SwiftUI
import UnliRiceCore

/// A tree of a repository's branches.
///
/// **Two modes, and the difference is stated on screen.** Refs record where branches
/// point, never how they relate — so the in-app scanner alone can only draw a flat fan
/// off the trunk. When `check-repos.sh --json` has published ancestry, this draws the
/// real thing: each branch hanging off the branch it actually builds on, with the number
/// of commits between them.
///
/// The app never computes ancestry itself. It is sandboxed and cannot run git, and a
/// partial commit-object reader would answer confidently and wrongly on any established
/// repo. Unknown is rendered as unknown, and the legend says which mode you are looking at.
struct BranchGraphView: View {
    let snapshot: GitRepoScanner.Snapshot
    /// Published by the script. Nil when it has never run for this repo.
    var ancestry: RepoSnapshotFile.Repo?
    var ancestryAge: Date?
    var ancestryStale: Bool = false

    private let laneGap: CGFloat = 26
    private let trunkX: CGFloat = 52
    private let indent: CGFloat = 20
    private let nodeR: CGFloat = 5.5

    // MARK: - Model

    /// Branches sharing a tip SHA are one point in history, not several — three abandoned
    /// worktree branches sit on 6fdce21, and separate rows would invent a divergence.
    private struct Row {
        let sha: String
        let names: [String]
        let onRemote: Bool
        let isCurrent: Bool
        let parentSHA: String?
        let aheadOfParent: Int?
        let aheadOfTrunk: Int?
        var depth: Int = 0
        /// True when the branch is an ANCESTOR of the trunk — already folded in.
        /// Nil aheadOfTrunk means unknown (no ancestry published), which is neither.
        var merged: Bool? = nil
    }

    private var trunkBranch: GitRepoScanner.Branch? {
        guard let name = snapshot.defaultBranch else { return nil }
        return snapshot.branches.first { $0.name == name }
    }

    private var trunkNames: [String] {
        guard let sha = trunkBranch?.sha else { return [] }
        return snapshot.branches.filter { $0.sha == sha }.map(\.name).sorted()
    }

    private var hasAncestry: Bool { ancestry?.hasAncestry == true }

    /// Rows in draw order, already nested. Without ancestry every row is depth 0, which is
    /// the honest flat fan; with it, depth is the length of the parent chain.
    private var rows: [Row] {
        let trunkSHA = trunkBranch?.sha
        let byName = Dictionary(snapshot.branches.map { ($0.name, $0) }) { a, _ in a }
        let anc = Dictionary((ancestry?.branches ?? []).map { ($0.name, $0) }) { a, _ in a }

        // Group by tip SHA, carrying whichever ancestry the members supply.
        var grouped: [String: Row] = [:]
        for b in snapshot.branches where b.sha != trunkSHA {
            let a = anc[b.name]
            // A parent is usable only if it resolves to a SHA we are actually drawing,
            // and it must be neither the trunk (those hang off the trunk directly), nor
            // this same commit (an alias, not a parent), nor itself.
            var pSHA: String?
            if let p = a?.parent, p != b.name,
               let pb = byName[p], pb.sha != trunkSHA, pb.sha != b.sha {
                pSHA = pb.sha
            }
            if let e = grouped[b.sha] {
                grouped[b.sha] = Row(sha: b.sha,
                                     names: (e.names + [b.name]).sorted(),
                                     onRemote: e.onRemote || b.tipOnRemote,
                                     isCurrent: e.isCurrent || b.isCurrent,
                                     parentSHA: e.parentSHA ?? pSHA,
                                     aheadOfParent: e.aheadOfParent ?? a?.aheadOfParent,
                                     aheadOfTrunk: e.aheadOfTrunk ?? a?.aheadOfTrunk,
                                     merged: (e.aheadOfTrunk ?? a?.aheadOfTrunk).map { $0 == 0 })
            } else {
                grouped[b.sha] = Row(sha: b.sha, names: [b.name],
                                     onRemote: b.tipOnRemote, isCurrent: b.isCurrent,
                                     parentSHA: pSHA,
                                     aheadOfParent: a?.aheadOfParent,
                                     aheadOfTrunk: a?.aheadOfTrunk,
                                     merged: a?.aheadOfTrunk.map { $0 == 0 })
            }
        }

        func key(_ r: Row) -> (Int, Int, String) {
            (r.isCurrent ? 0 : 1, r.onRemote ? 1 : 0, r.names.first ?? "")
        }
        let kids = Dictionary(grouping: grouped.values.compactMap { r -> (String, Row)? in
            guard let p = r.parentSHA, grouped[p] != nil else { return nil }
            return (p, r)
        }, by: \.0).mapValues { $0.map(\.1) }

        // Depth-first, so a child always sits directly beneath its parent.
        var out: [Row] = []
        var visited = Set<String>()
        func walk(_ r: Row, _ depth: Int) {
            guard visited.insert(r.sha).inserted else { return }   // cycle guard
            var r = r
            r.depth = depth
            out.append(r)
            for k in (kids[r.sha] ?? []).sorted(by: { key($0) < key($1) }) {
                walk(k, depth + 1)
            }
        }
        for r in grouped.values.filter({ $0.parentSHA == nil || grouped[$0.parentSHA!] == nil })
            .sorted(by: { key($0) < key($1) }) {
            walk(r, 0)
        }
        // Anything still unvisited sits in a cycle the guard broke — draw it, don't drop it.
        for r in grouped.values.sorted(by: { key($0) < key($1) }) where !visited.contains(r.sha) {
            walk(r, 0)
        }
        return out
    }

    /// Ahead of the trunk — real forks, work that is not on the trunk yet.
    private var liveRows: [Row] { rows.filter { $0.merged != true } }
    /// Ancestors of the trunk. These are BEHIND it, already folded in.
    ///
    /// The bug this split fixes (2026-09-02): every branch was drawn as a fork above the
    /// trunk. In Nuptia all 15 branches are merged — `git branch --merged main` agrees —
    /// so the graph read as "fifteen branches building on each other off main" when the
    /// truth was "fifteen dead branches already folded into main". Inverting the meaning
    /// is worse than drawing nothing.
    private var mergedRows: [Row] { rows.filter { $0.merged == true } }

    private var height: CGFloat { CGFloat(rows.count + 1) * laneGap + 30 }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            Canvas { ctx, _ in draw(ctx) }
                .frame(height: height)
                .overlay(alignment: .topLeading) { labels }
        }
    }

    private var legend: some View {
        HStack(spacing: 11) {
            dot(Theme.textSecondary); caption("on a remote")
            dot(.orange); caption("local only")
            if hasAncestry {
                caption("· above the trunk = ahead of it · below = already merged in")
                if ancestryStale, let age = ancestryAge {
                    Text("· ancestry \(age.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange)
                }
            } else {
                // Say why it is flat, so it does not read as "nothing is nested".
                caption("· flat — run check-repos.sh --json for real nesting")
            }
            Spacer(minLength: 0)
        }
    }

    private func dot(_ c: Color) -> some View {
        Circle().strokeBorder(c, lineWidth: 2).frame(width: 9, height: 9)
    }
    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.textSecondary).lineLimit(1)
    }
    private func tag(_ s: String, _ c: Color) -> some View {
        Text(s).font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(c)
    }

    private func draw(_ ctx: GraphicsContext) {
        let live = liveRows, merged = mergedRows
        let top: CGFloat = 10
        func y(_ i: Int) -> CGFloat { top + CGFloat(i) * laneGap + 13 }
        func x(_ d: Int) -> CGFloat { trunkX + CGFloat(d + 1) * indent }
        // The trunk sits BETWEEN the two groups: forks above it, history below.
        let trunkY = y(live.count)
        let rows = live + merged

        let bottom = y(rows.count + (merged.isEmpty ? 0 : 1))
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: trunkX, y: top))
            p.addLine(to: CGPoint(x: trunkX, y: max(trunkY, bottom)))
        }, with: .color(Color.accentColor.opacity(0.5)), lineWidth: 2)

        // Merged rows are pushed one slot down to leave room for the trunk node.
        func slot(_ i: Int) -> Int { i < live.count ? i : i + 1 }

        var pos: [String: CGPoint] = [:]
        for (i, r) in rows.enumerated() { pos[r.sha] = CGPoint(x: x(r.depth), y: y(slot(i))) }

        for (i, r) in rows.enumerated() {
            let c = CGPoint(x: x(r.depth), y: y(slot(i)))
            // Merged branches are history, not work: muted, never orange-as-alarm.
            let color: Color = r.merged == true
                ? Color.secondary.opacity(0.45)
                : (r.onRemote ? Color.secondary : .orange)
            // An edge to the branch this one builds on, or to the trunk.
            let from = r.parentSHA.flatMap { pos[$0] } ?? CGPoint(x: trunkX, y: trunkY)

            ctx.stroke(Path { p in
                p.move(to: from)
                p.addCurve(to: c,
                           control1: CGPoint(x: from.x, y: c.y),
                           control2: CGPoint(x: from.x + 8, y: c.y))
            }, with: .color(color.opacity(0.6)), lineWidth: 1.8)

            let d = CGRect(x: c.x - nodeR, y: c.y - nodeR, width: nodeR * 2, height: nodeR * 2)
            ctx.fill(Path(ellipseIn: d.insetBy(dx: -2.5, dy: -2.5)),
                     with: .color(Color(nsColor: .windowBackgroundColor)))
            ctx.stroke(Path(ellipseIn: d), with: .color(color), lineWidth: 2)
            if r.isCurrent {
                ctx.fill(Path(ellipseIn: d.insetBy(dx: 1.5, dy: 1.5)), with: .color(color))
            }
        }

        if trunkBranch != nil {
            let d = CGRect(x: trunkX - nodeR, y: trunkY - nodeR,
                           width: nodeR * 2, height: nodeR * 2)
            ctx.fill(Path(ellipseIn: d.insetBy(dx: -3, dy: -3)),
                     with: .color(Color(nsColor: .windowBackgroundColor)))
            ctx.fill(Path(ellipseIn: d.insetBy(dx: -1, dy: -1)), with: .color(Color.accentColor))
        }
    }

    private var labels: some View {
        let live = liveRows, merged = mergedRows
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(live.enumerated()), id: \.offset) { _, r in row(r) }

            if let t = trunkBranch {
                HStack(spacing: 6) {
                    Text(trunkNames.joined(separator: "  ·  "))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    tag("TRUNK", Color.accentColor)
                    if trunkNames.count > 1 { tag("same commit", .orange.opacity(0.9)) }
                    // Say what the split means, right where the eye crosses it.
                    if !merged.isEmpty {
                        tag("\(merged.count) merged below", Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(String(t.sha.prefix(7)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(height: laneGap, alignment: .center)
                .padding(.leading, trunkX + 13)
                .padding(.trailing, 4)
            }

            ForEach(Array(merged.enumerated()), id: \.offset) { _, r in row(r) }
        }
        .padding(.top, 1)
        .allowsHitTesting(false)
    }

    private func row(_ r: Row) -> some View {
        let isMerged = r.merged == true
        return HStack(spacing: 6) {
            Text(r.names.joined(separator: "  ·  "))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isMerged ? Theme.textSecondary.opacity(0.65)
                                          : (r.isCurrent ? Theme.textPrimary : Theme.textSecondary))
                .lineLimit(1)
            if r.isCurrent { tag("HEAD", Theme.textSecondary) }
            if r.names.count > 1 { tag("same commit", .orange.opacity(0.9)) }
            if isMerged {
                // The actionable fact about these: nothing is on them that is not on
                // the trunk, so deleting them loses nothing.
                tag("merged", Theme.textSecondary.opacity(0.7))
            } else if r.parentSHA != nil, let n = r.aheadOfParent {
                tag("+\(n)", Theme.textSecondary)
            } else if let n = r.aheadOfTrunk, n > 0 {
                tag("+\(n) on trunk", Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Text(String(r.sha.prefix(7)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary.opacity(isMerged ? 0.65 : 1))
        }
        .frame(height: laneGap, alignment: .center)
        .padding(.leading, trunkX + CGFloat(r.depth + 1) * indent + 13)
        .padding(.trailing, 4)
    }
}
