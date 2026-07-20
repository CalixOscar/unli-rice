import SwiftUI
import UnliRiceCore

/// "Oh right, that's what February was."
///
/// The look-back screen, completely beautified to be pleasant, visual, and highly readable.
struct RetrospectiveView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let digest = store.retrospectiveDigest, !digest.isEmpty {
                    summaryRow(digest)
                    
                    if !digest.months.isEmpty {
                        monthsSection(digest)
                    }
                    
                    if !digest.contributors.isEmpty {
                        contributorsSection(digest)
                    }
                    
                    if !digest.projects.isEmpty {
                        tallySection(
                            "Where the time went",
                            digest.projects,
                            accent: Theme.violet,
                            icon: "briefcase.fill"
                        )
                    }
                    
                    if !digest.tags.isEmpty {
                        tallySection(
                            "What it was about",
                            Array(digest.tags.prefix(12)),
                            accent: Theme.accent,
                            icon: "tag.fill"
                        )
                    }
                    
                    if !digest.highlights.isEmpty {
                        highlightsSection(digest)
                    }
                } else {
                    emptyState
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.currentRetrospectivePeriod?.displayName() ?? "Your Review")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("built from your active notes")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.inkDim.opacity(0.8))
            }

            if store.retrospectivePeriods.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.retrospectivePeriods) { period in
                            let selected = period == store.currentRetrospectivePeriod
                            Button(action: { store.selectRetrospective(period) }) {
                                Text(period.displayName())
                                    .font(.system(
                                        size: 11,
                                        weight: period.span == .year ? .bold : .medium,
                                        design: .monospaced
                                    ))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selected ? Theme.accent : Color.white.opacity(0.04))
                                    .foregroundStyle(selected ? Theme.onAccent : Theme.inkDim)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(selected ? Color.clear : Theme.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func summaryRow(_ digest: RetrospectiveDigest) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            statCard(
                value: "\(digest.notesCreated)",
                label: "Notes Written",
                icon: "doc.text.fill",
                color: Theme.accent
            )

            statCard(
                value: "\(digest.notesRevisited)",
                label: "Notes Updated",
                icon: "arrow.up.doc.fill",
                color: Theme.brass
            )

            if let busiest = digest.busiestMonth {
                statCard(
                    value: busiest.period.displayName().components(separatedBy: " ").first ?? "—",
                    label: "Busiest Month",
                    icon: "calendar.badge.clock",
                    color: Theme.violet
                )
            } else if let project = digest.projects.first {
                statCard(
                    value: project.name,
                    label: "Top Project",
                    icon: "folder.fill",
                    color: Theme.violet
                )
            } else {
                statCard(
                    value: "—",
                    label: "Busiest Period",
                    icon: "calendar",
                    color: Theme.violet
                )
            }
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.inkDim.opacity(0.8))
            }
        }
        .padding(14)
        .background(Theme.panel.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }

    private func monthsSection(_ digest: RetrospectiveDigest) -> some View {
        Card(
            title: "Month by month",
            subtitle: "Activity trends over the selected period.",
            icon: "calendar"
        ) {
            VStack(spacing: 12) {
                let peak = max(digest.months.map(\.noteCount).max() ?? 1, 1)
                ForEach(digest.months) { month in
                    Button(action: { store.selectRetrospective(month.period) }) {
                        HStack(spacing: 14) {
                            Text(month.period.displayName().components(separatedBy: " ").first ?? "")
                                .font(.system(size: 12, weight: .semibold, design: .serif))
                                .foregroundStyle(month.noteCount > 0 ? Theme.ink : Theme.inkDim.opacity(0.4))
                                .frame(width: 70, alignment: .leading)

                            // Premium Capsule Progress Bar
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.04))
                                    .frame(height: 6)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Theme.accent.opacity(month.noteCount > 0 ? 0.8 : 0.0))
                                        .frame(width: max(geo.size.width * CGFloat(month.noteCount) / CGFloat(peak), month.noteCount > 0 ? 4 : 0))
                                }
                                .frame(height: 6)
                            }
                            .frame(width: 130)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(month.noteCount == 0 ? "Quiet" : "\(month.noteCount) note\(month.noteCount == 1 ? "" : "s")\(month.leadingProject.map { " · \($0)" } ?? "")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkDim)
                                if let highlight = month.highlight {
                                    Text(highlight.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.ink.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)

                    if month.id != digest.months.last?.id {
                        Divider().opacity(0.06)
                    }
                }
            }
        }
    }

    private func contributorsSection(_ digest: RetrospectiveDigest) -> some View {
        Card(
            title: "Who wrote it",
            subtitle: "Notes created and word count contributions.",
            icon: "person.2.fill"
        ) {
            VStack(spacing: 12) {
                let peak = max(digest.contributors.map(\.notesCreated).max() ?? 1, 1)
                ForEach(digest.contributors) { contributor in
                    HStack(spacing: 14) {
                        Text(contributor.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 120, alignment: .leading)

                        // Premium Capsule Progress Bar
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                                .frame(height: 6)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Theme.brass.opacity(0.8))
                                    .frame(width: contributor.notesCreated == 0
                                        ? 0
                                        : max(geo.size.width * CGFloat(contributor.notesCreated) / CGFloat(peak), 4))
                            }
                            .frame(height: 6)
                        }
                        .frame(width: 130)

                        Text("\(contributor.notesCreated) created")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.inkDim)
                            .frame(width: 80, alignment: .leading)

                        Text(detail(contributor))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.inkDim.opacity(0.7))
                            .lineLimit(1)

                        Spacer()
                    }

                    if contributor.id != digest.contributors.last?.id {
                        Divider().opacity(0.06)
                    }
                }
            }
        }
    }

    private func detail(_ contributor: ContributorTally) -> String {
        var parts: [String] = []
        if contributor.wordsWritten > 0 { parts.append("\(words(contributor.wordsWritten)) words") }
        if contributor.notesTouched > 0 { parts.append("+\(contributor.notesTouched) edited") }
        return parts.joined(separator: " · ")
    }

    private func words(_ count: Int) -> String {
        count < 1000 ? "\(count)" : String(format: "%.1fk", Double(count) / 1000)
    }

    private func tallySection(_ title: String, _ tallies: [RetrospectiveTally], accent: Color, icon: String) -> some View {
        Card(
            title: title,
            subtitle: "Breakdown of work across sections.",
            icon: icon
        ) {
            VStack(spacing: 12) {
                let peak = max(tallies.first?.count ?? 1, 1)
                ForEach(tallies) { tally in
                    HStack(spacing: 14) {
                        Text(tally.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 120, alignment: .leading)

                        // Premium Capsule Progress Bar
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                                .frame(height: 6)
                            GeometryReader { geo in
                                Capsule()
                                    .fill(accent.opacity(0.8))
                                    .frame(width: max(geo.size.width * CGFloat(tally.count) / CGFloat(peak), 4))
                            }
                            .frame(height: 6)
                        }
                        .frame(width: 130)

                        Text("\(tally.count) note\(tally.count == 1 ? "" : "s")")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.inkDim)

                        Spacer()
                    }

                    if tally.id != tallies.last?.id {
                        Divider().opacity(0.06)
                    }
                }
            }
        }
    }

    private func highlightsSection(_ digest: RetrospectiveDigest) -> some View {
        Card(
            title: "Worth remembering",
            subtitle: "Notes ranked by how often other notes link back to them.",
            icon: "sparkles"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(digest.highlights) { note in
                    Button(action: { store.openHighlight(note) }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.title)
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 12) {
                                Label(note.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                if !note.backlinks.isEmpty {
                                    Label("\(note.backlinks.count) link\(note.backlinks.count == 1 ? "" : "s")", systemImage: "link")
                                }
                                if let project = Retrospective.project(of: note) {
                                    Label(project, systemImage: "folder")
                                }
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkDim.opacity(0.8))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel.opacity(0.4))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to look back on yet.")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("""
                This screen fills itself in from notes you already have — nothing \
                extra to switch on or remember. Come back after a month of use.
                """)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim.opacity(0.8))
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}
