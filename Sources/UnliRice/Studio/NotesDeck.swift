import SwiftUI
import UnliRiceCore

struct NotesDeck: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    private var scoped: GardenCrate.Sleeve? { store.studioScope == .project ? store.studioFrontSleeve : nil }
    private var open: [Note] {
        let ids = scoped.map { Set($0.noteIDs) }
        return store.notes.filter { note in
            !note.archived && (ids.map { $0.contains(note.id) } ?? true)
        }
    }
    private var needYou: Int {
        guard let scoped else { return store.pending.count + store.unreadNoticeCount }
        let ids = Set(scoped.noteIDs)
        return store.pending.filter { ids.contains($0.note.id) }.count
    }
    private var newest: [Note] { Array(open.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)) }
    private var buckets: [(String, Int)] {
        ["claude", "codex", "human", "ingest", "other"].map { name in
            (name, open.filter { creatorBucket($0.creator) == name }.count)
        }
    }

    var body: some View {
        Group {
            if let error = store.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Can't read your notes").font(.system(size: 17, weight: .semibold))
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text(scoped.map { "For \($0.name)" } ?? "All projects")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if let scoped, open.isEmpty {
                        Text("No notes for \(scoped.name) yet. A note tagged \(scoped.name) shows up here.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        HStack(alignment: .center, spacing: 16) {
                            ring
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                                    HStack(spacing: 6) {
                                        Circle().fill(Color(studio: .notes, scheme: colorScheme).opacity([1.0, 0.7, 0.45, 0.28, 0.15][index]))
                                            .frame(width: 7, height: 7)
                                        Text("\(bucket.0) \(bucket.1)")
                                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                        }
                        Text("\(needYou) need you · newest by \(newest.first?.creator ?? "—")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(newest) { note in
                            Button(note.title) { store.selectNote(note.id) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(Theme.textSecondary.opacity(0.12), lineWidth: 14)
            let total = max(open.count, 1)
            ForEach(Array(buckets.enumerated()), id: \.offset) { index, bucket in
                Circle()
                    .trim(from: start(for: index, total: total), to: end(for: index, total: total))
                    .stroke(Color(studio: .notes, scheme: colorScheme).opacity([1.0, 0.7, 0.45, 0.28, 0.15][index]), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Text("\(open.count)")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(width: 180, height: 180)
    }

    private func creatorBucket(_ creator: String) -> String {
        switch creator.lowercased() {
        case "claude", "codex", "human", "ingest": return creator.lowercased()
        default: return "other"
        }
    }

    private func start(for index: Int, total: Int) -> CGFloat {
        CGFloat(buckets.prefix(index).reduce(0) { $0 + $1.1 }) / CGFloat(total)
    }

    private func end(for index: Int, total: Int) -> CGFloat {
        CGFloat(buckets.prefix(index + 1).reduce(0) { $0 + $1.1 }) / CGFloat(total)
    }
}
