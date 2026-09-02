import SwiftUI
import UnliRiceCore

/// What is outstanding across the studio, in the order it would hurt to ignore.
///
/// **Nothing here can be ticked off**, by design. Every line is derived from the state
/// that makes it true, so it disappears when the work is done rather than when someone
/// remembers to mark it. A checklist you tick is a second source of truth, and this
/// codebase has already paid for notes that disagree with the repo.
///
/// It reads two things: the published repo snapshot, and each project's `memory.md`
/// `**Next step:**`. Git tells you what is at risk; the note tells you what you meant
/// to do. Neither alone is the list.
struct TodoPaneView: View {
    @EnvironmentObject var store: AppStore

    @State private var todo: StudioTodo = .init(items: [])
    @State private var loading = false
    @State private var loaded = false
    @State private var sourceNote: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if loading {
                    ProgressView().padding(.vertical, 24)
                } else if todo.items.isEmpty && loaded {
                    empty
                } else {
                    ForEach(StudioTodo.Kind.allCases, id: \.rawValue) { kind in
                        let items = todo.items.filter { $0.kind == kind }
                        if !items.isEmpty { section(kind, items) }
                    }
                }
            }
            .padding(22)
        }
        .task { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To do")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Derived from your repositories and each project's memory.md. Nothing "
                 + "here is ticked off — an item disappears when the work is actually "
                 + "done, so the list cannot drift from what is true.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !sourceNote.isEmpty {
                Text(sourceNote)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Nothing outstanding")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Every branch tip is on a remote, no worktree holds uncommitted work, "
                 + "and no memory.md names a next step. If that seems wrong, publish a "
                 + "fresh snapshot: check-repos.sh --publish")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 12)
    }

    private func section(_ kind: StudioTodo.Kind, _ items: [StudioTodo.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(kind.label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(kind == .atRisk ? .orange : Theme.textSecondary)
                Text(kindBlurb(kind))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Text("\(items.count)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(items) { row($0, kind) }
        }
    }

    /// Says why the group is where it is, so the ordering is not arbitrary.
    private func kindBlurb(_ k: StudioTodo.Kind) -> String {
        switch k {
        case .atRisk:   return "exists on this Mac only — losing the disk loses it"
        case .declared: return "you wrote this down as the next step"
        case .unshared: return "finished, but nobody else can see it"
        case .clutter:  return "costs nothing to leave, but hides the rest"
        }
    }

    private func row(_ item: StudioTodo.Item, _ kind: StudioTodo.Kind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.project)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(item.evidence)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let fix = item.fix {
                // Shown, never run. This pane reports; the founder acts.
                Text(fix)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 7)
                    .background(Theme.bgField, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlass(cornerRadius: 10)
        .overlay(alignment: .leading) {
            if kind == .atRisk {
                Rectangle().fill(Color.orange).frame(width: 2)
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        loading = true
        defer { loading = false; loaded = true }

        let folder = store.dataURL.deletingLastPathComponent()
        let roots = store.scanRoots

        let result: (StudioTodo, String) = await Task.detached(priority: .userInitiated) {
            let needsStop = folder.startAccessingSecurityScopedResource()
            defer { if needsStop { folder.stopAccessingSecurityScopedResource() } }

            guard let snap = try? RepoSnapshotFile.read(fromFolder: folder) else {
                return (StudioTodo(items: []),
                        "no snapshot in \(folder.path) — run check-repos.sh --publish")
            }

            // memory.md lives in each project, under folders already granted for
            // scanning. Missing is normal: only one project has one so far.
            var steps: [String: String] = [:]
            let opened = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (u, ok) in opened where ok { u.stopAccessingSecurityScopedResource() } }
            for (root, _) in opened {
                guard let kids = try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                else { continue }
                for kid in kids {
                    let m = kid.appendingPathComponent("memory.md")
                    guard let body = try? String(contentsOf: m, encoding: .utf8),
                          let step = StudioTodo.nextStep(fromMemory: body) else { continue }
                    steps[kid.lastPathComponent] = step
                }
            }

            let dirt = Dictionary(uniqueKeysWithValues: snap.repos.map { ($0.name, 0) })
            let t = StudioTodo.derive(from: snap, nextSteps: steps, worktreeDirt: dirt)
            return (t, "\(snap.repos.count) repos · \(steps.count) memory.md · snapshot "
                     + snap.generatedAt.formatted(.relative(presentation: .named)))
        }.value

        todo = result.0
        sourceNote = result.1
    }
}
