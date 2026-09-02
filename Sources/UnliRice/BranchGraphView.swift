import SwiftUI
import UnliRiceCore

/// A trunk-and-lanes drawing of a repository's branches.
///
/// **What this is, precisely.** It is a *ref* graph, not a commit graph. Refs record where
/// each branch points; they do not record ancestry. Drawing true topology — who descends
/// from whom, how far apart two branches are — needs a walk over commit objects, which are
/// zlib-deflated when loose and inside packfiles when not. A partial reader would render
/// confident-looking history that stops at the first packed commit, which on any
/// established repo is almost immediately. So this draws only what refs can prove:
///
///   * the trunk, and every branch as a lane leaving it
///   * branches sharing a tip SHA collapsed onto ONE node, because they are the same commit
///   * whether each tip exists on a remote
///
/// Distance along a lane carries no meaning and is deliberately uniform — nothing here
/// implies "3 commits ahead", because refs cannot support that claim.
struct BranchGraphView: View {
    let snapshot: GitRepoScanner.Snapshot

    private let laneGap: CGFloat = 26
    private let trunkX: CGFloat = 74
    private let nodeR: CGFloat = 5.5

    /// The trunk branch, and the SHA it points at. Everything else forks from here.
    private var trunk: GitRepoScanner.Branch? {
        guard let name = snapshot.defaultBranch else { return nil }
        return snapshot.branches.first { $0.name == name }
    }

    /// Branches sharing a tip are one point in history. Unli Rice has three abandoned
    /// worktree branches all sitting on 6fdce21; drawing them as three separate lanes
    /// would invent a divergence that does not exist.
    ///
    /// Branches sitting on the TRUNK'S OWN SHA are excluded — they have not diverged from
    /// it at all, so they belong on the trunk node as extra labels rather than as forks.
    /// `feature/design-system` is exactly this: it points at main's tip, so drawing it as
    /// a lane invented a branch that does not exist.
    private var clusters: [(sha: String, names: [String], onRemote: Bool, isCurrent: Bool)] {
        let trunkSHA = trunk?.sha
        return Dictionary(grouping: snapshot.branches.filter { $0.sha != trunkSHA }, by: \.sha)
            .map { sha, group in
                (sha: sha,
                 names: group.map(\.name).sorted(),
                 onRemote: group.contains { $0.tipOnRemote },
                 isCurrent: group.contains { $0.isCurrent })
            }
            .sorted { a, b in
                if a.isCurrent != b.isCurrent { return a.isCurrent }
                if a.onRemote != b.onRemote { return !a.onRemote }
                return a.names[0] < b.names[0]
            }
    }

    /// Every branch that IS the trunk commit — `main` plus anything pointing at it.
    private var trunkNames: [String] {
        guard let trunkSHA = trunk?.sha else { return [] }
        return snapshot.branches.filter { $0.sha == trunkSHA }.map(\.name).sorted()
    }

    private var height: CGFloat { CGFloat(clusters.count + 1) * laneGap + 34 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                legendDot(Theme.textSecondary, filled: false)
                Text("on a remote").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                legendDot(.orange, filled: false)
                Text("local only").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text("· forks from \(snapshot.defaultBranch ?? "the trunk") · lane length is not a commit count")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            Canvas { ctx, size in
                let clusters = self.clusters
                guard !clusters.isEmpty else { return }

                let trunkTop: CGFloat = 12
                let trunkBottom = CGFloat(clusters.count) * laneGap + 6

                // The trunk. It stops at the last fork because there is nothing below it.
                ctx.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: trunkX, y: trunkTop))
                        p.addLine(to: CGPoint(x: trunkX, y: trunkBottom))
                    },
                    with: .color(Color.accentColor.opacity(0.55)), lineWidth: 2)

                // The trunk's own node. Branches fork ABOVE it; it is the common origin,
                // so it sits at the foot of the line rather than being one lane among many.
                if trunk != nil {
                    let ty = trunkBottom
                    let d = CGRect(x: trunkX - nodeR, y: ty - nodeR,
                                   width: nodeR * 2, height: nodeR * 2)
                    ctx.fill(Path(ellipseIn: d.insetBy(dx: -3, dy: -3)),
                             with: .color(Color(nsColor: .windowBackgroundColor)))
                    ctx.fill(Path(ellipseIn: d.insetBy(dx: -1, dy: -1)),
                             with: .color(Color.accentColor))
                }

                for (i, c) in clusters.enumerated() {
                    let y = trunkTop + CGFloat(i) * laneGap + 14
                    let endX = min(size.width - 16, trunkX + 46)
                    let color: Color = c.onRemote ? Color.secondary : .orange

                    // Curve out of the trunk, the way a git graph renderer draws a fork.
                    ctx.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: trunkX, y: y - laneGap + 2))
                            p.addCurve(
                                to: CGPoint(x: endX, y: y),
                                control1: CGPoint(x: trunkX, y: y),
                                control2: CGPoint(x: trunkX + 16, y: y))
                        },
                        with: .color(color.opacity(0.7)), lineWidth: 2)

                    let dot = CGRect(x: endX - nodeR, y: y - nodeR,
                                     width: nodeR * 2, height: nodeR * 2)
                    ctx.fill(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)),
                             with: .color(Color(nsColor: .windowBackgroundColor)))
                    ctx.stroke(Path(ellipseIn: dot), with: .color(color), lineWidth: 2)
                    if c.isCurrent {
                        ctx.fill(Path(ellipseIn: dot.insetBy(dx: 1.5, dy: 1.5)),
                                 with: .color(color))
                    }
                }
            }
            .frame(height: height)
            .overlay(alignment: .topLeading) { labels }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(clusters.enumerated()), id: \.offset) { i, c in
                HStack(spacing: 6) {
                    // Several names on one node is the interesting case, not a rendering
                    // problem: those branches are literally the same commit.
                    Text(c.names.joined(separator: "  ·  "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(c.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                    if c.isCurrent {
                        Text("HEAD")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if c.names.count > 1 {
                        Text("same commit")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                    Text(String(c.sha.prefix(7)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(height: laneGap, alignment: .center)
                .padding(.leading, trunkX + 60)
                .padding(.trailing, 4)
            }

            if let t = trunk {
                HStack(spacing: 6) {
                    Text(trunkNames.joined(separator: "  ·  "))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("TRUNK")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    if trunkNames.count > 1 {
                        Text("same commit")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                    Text(String(t.sha.prefix(7)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(height: laneGap, alignment: .center)
                .padding(.leading, trunkX + 60)
                .padding(.trailing, 4)
            }
        }
        .padding(.top, 2)
        .allowsHitTesting(false)
    }

    private func legendDot(_ c: Color, filled: Bool) -> some View {
        Circle()
            .strokeBorder(c, lineWidth: 2)
            .background(Circle().fill(filled ? c : .clear))
            .frame(width: 9, height: 9)
    }
}
