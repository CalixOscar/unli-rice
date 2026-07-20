import SwiftUI
import UnliRiceCore

/// "Oh right, that's what February was."
///
/// The one screen in this app that exists to be *pleasant* rather than useful.
/// Everything else here earns its place by making the corpus better; this one
/// earns its place by making a year of it worth having kept.
///
/// It shows counts, but counts are not the point and the layout says so — the
/// numbers are a header, and the body of the screen is titles you'd forgotten
/// writing. A dashboard would be the wrong answer to "what did I do this year".
struct RetrospectiveView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let digest = store.retrospectiveDigest, !digest.isEmpty {
                    summaryRow(digest)
                    if !digest.contributors.isEmpty { contributorsSection(digest) }
                    if !digest.months.isEmpty { monthsSection(digest) }
                    if !digest.projects.isEmpty {
                        tallySection("Where the time went", digest.projects, accent: Theme.violet)
                    }
                    if !digest.tags.isEmpty {
                        tallySection("What it was about", Array(digest.tags.prefix(12)), accent: Theme.accent)
                    }
                    if !digest.highlights.isEmpty { highlightsSection(digest) }
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.currentRetrospectivePeriod?.displayName() ?? "Your review")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("built from notes you already have")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }

            // Period picker. Months first because a month is the unit that
            // finishes; the year sits among them rather than in its own control,
            // since picking "2026" is the same kind of act as picking "June".
            if store.retrospectivePeriods.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.retrospectivePeriods) { period in
                            let selected = period == store.currentRetrospectivePeriod
                            Button(action: { store.selectRetrospective(period) }) {
                                Text(period.displayName())
                                    .font(.system(
                                        size: 10.5,
                                        weight: period.span == .year ? .semibold : .regular,
                                        design: .monospaced
                                    ))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(selected ? Theme.accentSoft : Color.white.opacity(0.04))
                                    .foregroundStyle(selected ? Theme.accent : Theme.inkDim)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private func summaryRow(_ digest: RetrospectiveDigest) -> some View {
        HStack(alignment: .top, spacing: 26) {
            stat("\(digest.notesCreated)", "note\(digest.notesCreated == 1 ? "" : "s") written")
            if digest.notesRevisited > 0 {
                stat("\(digest.notesRevisited)", "older note\(digest.notesRevisited == 1 ? "" : "s") added to")
            }
            if let busiest = digest.busiestMonth {
                stat(busiest.period.displayName().components(separatedBy: " ").first ?? "—", "busiest month")
            }
            if let project = digest.projects.first {
                stat(project.name, "most-worked project")
            }
            if let author = digest.contributors.first(where: { $0.notesCreated > 0 }) {
                stat(author.name, "wrote the most")
            }
            Spacer()
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.brass)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkDim)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The year view's spine: one row per month, so a year reads as a shape
    /// rather than a total.
    private func monthsSection(_ digest: RetrospectiveDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Month by month")
            let peak = max(digest.months.map(\.noteCount).max() ?? 1, 1)
            ForEach(digest.months) { month in
                Button(action: { store.selectRetrospective(month.period) }) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(month.period.displayName().components(separatedBy: " ").first ?? "")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(month.noteCount > 0 ? Theme.ink : Theme.inkDim.opacity(0.5))
                            .frame(width: 76, alignment: .leading)

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent.opacity(month.noteCount > 0 ? 0.55 : 0.0))
                                .frame(width: max(geo.size.width * CGFloat(month.noteCount) / CGFloat(peak), month.noteCount > 0 ? 3 : 0))
                        }
                        .frame(width: 90, height: 10)
                        .padding(.top, 3)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(month.noteCount == 0 ? "quiet" : "\(month.noteCount) note\(month.noteCount == 1 ? "" : "s")\(month.leadingProject.map { " · \($0)" } ?? "")")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkDim)
                            if let highlight = month.highlight {
                                Text(highlight.title)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.ink.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Who wrote the period.
    ///
    /// The corpus is written by several agents at once, and every other section
    /// here reported that as if it came from nowhere. The bar is *authorship* —
    /// notes started — because that's the number the row is claiming; edits and
    /// words sit beside it as detail rather than competing for the same length.
    private func contributorsSection(_ digest: RetrospectiveDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Who wrote it")
            let peak = max(digest.contributors.map(\.notesCreated).max() ?? 1, 1)
            ForEach(digest.contributors) { contributor in
                HStack(spacing: 10) {
                    Text(contributor.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.ink.opacity(0.9))
                        .lineLimit(1)
                        .frame(width: 190, alignment: .leading)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.brass.opacity(0.55))
                            .frame(width: contributor.notesCreated == 0
                                ? 0
                                : max(geo.size.width * CGFloat(contributor.notesCreated) / CGFloat(peak), 3))
                    }
                    .frame(height: 8)

                    Text("\(contributor.notesCreated)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                        .frame(width: 26, alignment: .trailing)

                    Text(detail(contributor))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkDim.opacity(0.75))
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                }
            }
        }
    }

    /// The two things a bare note count leaves out: how much was actually
    /// written, and the work done on notes somebody else started.
    private func detail(_ contributor: ContributorTally) -> String {
        var parts: [String] = []
        if contributor.wordsWritten > 0 { parts.append("\(words(contributor.wordsWritten)) words") }
        if contributor.notesTouched > 0 { parts.append("+\(contributor.notesTouched) edited") }
        return parts.joined(separator: " · ")
    }

    private func words(_ count: Int) -> String {
        count < 1000 ? "\(count)" : String(format: "%.1fk", Double(count) / 1000)
    }

    private func tallySection(_ title: String, _ tallies: [RetrospectiveTally], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            let peak = max(tallies.first?.count ?? 1, 1)
            ForEach(tallies) { tally in
                HStack(spacing: 10) {
                    Text(tally.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.ink.opacity(0.9))
                        .lineLimit(1)
                        .frame(width: 190, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent.opacity(0.5))
                            .frame(width: max(geo.size.width * CGFloat(tally.count) / CGFloat(peak), 3))
                    }
                    .frame(height: 8)
                    Text("\(tally.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    private func highlightsSection(_ digest: RetrospectiveDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Worth remembering")
            Text("Ranked by how often the rest of your notes point back at them.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkDim)
            ForEach(digest.highlights) { note in
                Button(action: { store.openHighlight(note) }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Text(note.createdAt.formatted(date: .abbreviated, time: .omitted))
                            if !note.backlinks.isEmpty {
                                Text("\(note.backlinks.count) note\(note.backlinks.count == 1 ? "" : "s") link here")
                            }
                            if let project = Retrospective.project(of: note) {
                                Text(project)
                            }
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to look back on yet.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
            Text("""
                This screen fills itself in from notes you already have — nothing \
                extra to switch on or remember. Come back after a month of use.
                """)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.inkDim)
    }
}
