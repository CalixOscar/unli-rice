import SwiftUI
import UnliRiceCore

/// The trunk as a line, and every branch drawn as what its history actually is.
///
/// **Three shapes, and only one is true of a given branch.**
/// - **loop** — it left the trunk and came back. Drawn as a siding: out at the fork
///   commit, alongside for however long it ran, back in at the merge. Two junctions.
/// - **open** — it left and has not come back. Out at the fork, ending in an open node.
/// - **tick** — it never left. The label sits on the trunk's own line, because the tip
///   *is* its own merge-base and there is no siding to draw.
///
/// Positions are to scale: a junction's distance down the line is its distance back
/// along the trunk in commits. A siding that ran alongside main for 74 commits looks
/// like one; a branch merged the next day looks like that.
///
/// **Loops belong to merge commits, not branches.** Repo-level loops are drawn even when
/// no branch label survives on them — otherwise most of the real history is invisible,
/// since a label that was merged and left alone gets overtaken and reads as a tick.
///
/// Without published ancestry none of this is knowable, and the view says so rather than
/// defaulting every branch into a shape it has not earned.
struct BranchGraphView: View {
    let snapshot: GitRepoScanner.Snapshot
    var ancestry: RepoSnapshotFile.Repo?
    var ancestryAge: Date?
    var ancestryStale: Bool = false

    private let trunkX: CGFloat = 26
    private let sidingX: CGFloat = 62
    private let rowH: CGFloat = 22
    private let nodeR: CGFloat = 4.5

    // MARK: - Model

    private struct Feature: Identifiable {
        let id = UUID()
        let names: [String]
        let sha: String
        let shape: String            // loop | open | tick
        let forkBack: Int
        let rejoinBack: Int?
        let siding: Int
        let onRemote: Bool
        let isCurrent: Bool
        let orphanLoop: Bool         // a loop with no surviving branch label
        let subject: String?
    }

    private var hasAncestry: Bool { ancestry?.hasAncestry == true }
    private var trunkLength: Int { max(ancestry?.trunkLength ?? 0, 1) }

    private var trunkBranch: GitRepoScanner.Branch? {
        guard let n = snapshot.defaultBranch else { return nil }
        return snapshot.branches.first { $0.name == n }
    }
    private var trunkNames: [String] {
        guard let sha = trunkBranch?.sha else { return [] }
        return snapshot.branches.filter { $0.sha == sha }.map(\.name).sorted()
    }

    /// Everything to draw, ordered newest-first down the line.
    private var features: [Feature] {
        guard let anc = ancestry else { return [] }
        let byName = Dictionary(anc.branches.map { ($0.name, $0) }) { a, _ in a }
        let trunkSHA = trunkBranch?.sha

        // Group live branches by tip, so two labels on one commit are one feature.
        var out: [Feature] = []
        var claimedMerges = Set<String>()
        let grouped = Dictionary(grouping: snapshot.branches.filter { $0.sha != trunkSHA },
                                 by: \.sha)

        for (sha, group) in grouped {
            let a = group.compactMap { byName[$0.name] }.first
            let shape = a?.shape ?? "tick"
            if let r = a?.rejoinSha { claimedMerges.insert(r) }
            out.append(Feature(
                names: group.map(\.name).sorted(),
                sha: sha,
                shape: shape,
                forkBack: a?.forkBack ?? a?.behindTrunk ?? 0,
                rejoinBack: a?.rejoinBack,
                siding: a?.sidingCommits ?? 0,
                onRemote: group.contains { $0.tipOnRemote },
                isCurrent: group.contains { $0.isCurrent },
                orphanLoop: false,
                subject: nil))
        }

        // Loops nobody is standing on any more. Without these the picture claims a
        // history far flatter than the real one.
        for l in anc.loops ?? [] where !claimedMerges.contains(l.mergeSha) {
            out.append(Feature(
                names: [], sha: l.mergeSha, shape: "loop",
                forkBack: l.forkBack, rejoinBack: l.rejoinBack, siding: l.commits,
                onRemote: true, isCurrent: false, orphanLoop: true, subject: l.subject))
        }

        return out.sorted { ($0.forkBack, $0.names.first ?? "~") < ($1.forkBack, $1.names.first ?? "~") }
    }

    /// Only the stretch of trunk that actually has something on it, so a repo whose
    /// features all sit near the tip is not drawn as a mile of empty line.
    private var span: (top: Int, bottom: Int) {
        let f = features
        guard !f.isEmpty else { return (0, 1) }
        let deepest = f.map(\.forkBack).max() ?? 1
        return (0, max(deepest, 1))
    }

    private var height: CGFloat {
        max(CGFloat(features.count + 2) * rowH, 120)
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            if hasAncestry {
                HStack(alignment: .top, spacing: 0) {
                    Canvas { ctx, size in draw(ctx, size) }
                        .frame(width: sidingX + 46, height: height)
                    labels
                }
            } else {
                unknownState
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 11) {
            if hasAncestry {
                shapeKey("loop", Color.secondary); shapeKey("open", .orange)
                caption("· position = commits back along \(snapshot.defaultBranch ?? "the trunk")")
                if ancestryStale, let age = ancestryAge {
                    Text("· \(age.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange)
                }
            } else {
                caption("history unknown — run check-repos.sh --publish")
            }
            Spacer(minLength: 0)
        }
    }

    private var unknownState: some View {
        Text("No ancestry published for this repo, so where each branch forked and "
             + "whether it ever rejoined is unknown. The list below is what refs alone "
             + "can prove.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }

    private func shapeKey(_ s: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().strokeBorder(c, lineWidth: 2).frame(width: 8, height: 8)
            Text(s).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
        }
    }
    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.textSecondary).lineLimit(1)
    }

    // MARK: - Drawing

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let f = features
        guard !f.isEmpty else { return }
        let s = span
        let top: CGFloat = 14
        let bottom = height - 14

        // Distance back along the trunk maps to distance down the line.
        func y(_ back: Int) -> CGFloat {
            let t = CGFloat(min(max(back, s.top), s.bottom) - s.top)
                  / CGFloat(max(s.bottom - s.top, 1))
            return top + t * (bottom - top)
        }

        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: trunkX, y: top))
            p.addLine(to: CGPoint(x: trunkX, y: bottom))
        }, with: .color(Color.accentColor.opacity(0.55)), lineWidth: 2.5)

        // The trunk tip.
        let tip = CGRect(x: trunkX - 5, y: top - 5, width: 10, height: 10)
        ctx.fill(Path(ellipseIn: tip), with: .color(Color.accentColor))

        for feat in f {
            let color: Color = feat.shape == "open"
                ? .orange
                : (feat.orphanLoop ? Color.secondary.opacity(0.4) : Color.secondary)
            let yFork = y(feat.forkBack)

            switch feat.shape {
            case "loop":
                let yJoin = y(feat.rejoinBack ?? feat.forkBack)
                // Out at the fork, alongside, back in at the merge — a passing loop.
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: trunkX, y: yFork))
                    p.addCurve(to: CGPoint(x: sidingX, y: yFork + 6),
                               control1: CGPoint(x: sidingX - 12, y: yFork),
                               control2: CGPoint(x: sidingX, y: yFork))
                    p.addLine(to: CGPoint(x: sidingX, y: max(yJoin - 6, yFork + 6)))
                    p.addCurve(to: CGPoint(x: trunkX, y: yJoin),
                               control1: CGPoint(x: sidingX, y: yJoin),
                               control2: CGPoint(x: sidingX - 12, y: yJoin))
                }, with: .color(color.opacity(0.8)), lineWidth: 1.8)
                junction(ctx, CGPoint(x: trunkX, y: yFork), color)
                junction(ctx, CGPoint(x: trunkX, y: yJoin), color)

            case "open":
                // Leaves and does not return: no second junction, open end.
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: trunkX, y: yFork))
                    p.addCurve(to: CGPoint(x: sidingX, y: yFork - 10),
                               control1: CGPoint(x: sidingX - 14, y: yFork),
                               control2: CGPoint(x: sidingX, y: yFork - 2))
                }, with: .color(color), lineWidth: 1.8)
                junction(ctx, CGPoint(x: trunkX, y: yFork), color)
                let e = CGRect(x: sidingX - nodeR, y: yFork - 10 - nodeR,
                               width: nodeR * 2, height: nodeR * 2)
                ctx.fill(Path(ellipseIn: e.insetBy(dx: -2, dy: -2)),
                         with: .color(Color(nsColor: .windowBackgroundColor)))
                ctx.stroke(Path(ellipseIn: e), with: .color(color), lineWidth: 2)

            default:
                // Never left the line: a mark on the trunk, not a siding.
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: trunkX - 5, y: yFork))
                    p.addLine(to: CGPoint(x: trunkX + 5, y: yFork))
                }, with: .color(color.opacity(0.55)), lineWidth: 1.4)
            }
        }
    }

    private func junction(_ ctx: GraphicsContext, _ p: CGPoint, _ c: Color) {
        let r = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
        ctx.fill(Path(ellipseIn: r.insetBy(dx: -1.5, dy: -1.5)),
                 with: .color(Color(nsColor: .windowBackgroundColor)))
        ctx.fill(Path(ellipseIn: r), with: .color(c))
    }

    // MARK: - Labels

    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(trunkNames.isEmpty ? (snapshot.defaultBranch ?? "trunk")
                                        : trunkNames.joined(separator: "  ·  "))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                tag("TRUNK", Color.accentColor)
                tag("\(trunkLength) commits", Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .frame(height: rowH, alignment: .center)

            ForEach(features) { f in
                HStack(spacing: 6) {
                    if f.orphanLoop {
                        Text(f.subject ?? "merge")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary.opacity(0.65))
                            .lineLimit(1)
                        tag("no branch left", Theme.textSecondary.opacity(0.6))
                    } else {
                        Text(f.names.joined(separator: "  ·  "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(f.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(1)
                        if f.isCurrent { tag("HEAD", Theme.textSecondary) }
                        if f.names.count > 1 { tag("same commit", .orange.opacity(0.9)) }
                    }

                    switch f.shape {
                    case "loop":
                        tag("\(f.siding) out, back after \(max(0, f.forkBack - (f.rejoinBack ?? f.forkBack)))",
                            Theme.textSecondary.opacity(0.8))
                    case "open":
                        tag("+\(f.siding), still out", .orange)
                    default:
                        tag("on the line", Theme.textSecondary.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    Text("\(f.forkBack) back")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .frame(height: rowH, alignment: .center)
            }
        }
        .padding(.top, 7)
        .allowsHitTesting(false)
    }

    private func tag(_ s: String, _ c: Color) -> some View {
        Text(s).font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(c)
    }
}
