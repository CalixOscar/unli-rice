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
    /// Kept so a prompt can carry the repo state the item was derived from.
    @State private var repos: [String: RepoSnapshotFile.Repo] = [:]

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
            Text("Derived from your repositories, each project's memory.md, and notes tagged `todo`. Nothing "
                 + "here is ticked off — an item disappears when the work is actually "
                 + "done, so the list cannot drift from what is true.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Always visible, not only on failure. The equivalent line on the Repos
            // pane is what turned "why is this empty" from an afternoon of elimination
            // into one launch.
            if !sourceNote.isEmpty {
                HStack(spacing: 8) {
                    Text(sourceNote)
                    if let gap = todo.coverage.gapSummary {
                        Text("·")
                        Text(gap)
                            .foregroundStyle(Theme.brass)
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
            }
        }
    }

    private var empty: some View {
        let state = TodoEmptyState.for(coverage: todo.coverage)
        return VStack(alignment: .leading, spacing: 5) {
            Text(state.headline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(emptyBody(for: state))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 12)
    }

    private func emptyBody(for state: TodoEmptyState) -> String {
        let folder = store.dataURL.deletingLastPathComponent().path
        switch state {
        case .unread:
            return "The snapshot at \(folder) could not be read, so this pane knows nothing about any repository. If you haven't published one yet, run: check-repos.sh --publish"
        case .emptySnapshot:
            return "The snapshot was read and listed no repositories. If that seems wrong, publish a fresh snapshot: check-repos.sh --publish"
        case .nothingOutstanding:
            let asOf = todo.coverage.generatedAt.map { " as of \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "Every branch tip is on a remote, no worktree holds uncommitted work, and no memory.md names a next step\(asOf). If that seems wrong, publish a fresh snapshot: check-repos.sh --publish"
        case .qualified(let message):
            let asOf = todo.coverage.generatedAt.map { ", as of \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "Every branch tip in the snapshot is on a remote, but: \(message)\(asOf). If that seems wrong, publish a fresh snapshot: check-repos.sh --publish"
        }
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
        case .atRisk:    return "exists on this Mac only — losing the disk loses it"
        case .declared:  return "you wrote this down as the next step"
        case .aiFlagged: return "an AI session flagged this, not you"
        case .unshared:  return "finished, but nobody else can see it"
        case .clutter:   return "costs nothing to leave, but hides the rest"
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
            // Only on declared next steps. At-risk and clutter items already carry an
            // exact command, and a menu on every row adds a decision to every line —
            // which teaches you to ignore it on the rows where the command was faster.
            if kind == .declared {
                AITodoMenu(item: item, repo: repos[item.project])
                    .padding(.top, 2)
            }
            if kind == .aiFlagged, let noteID = item.noteID, let note = store.note(id: noteID) {
                Button("Done") { store.archive(note); Task { await load() } }
                    .font(.system(size: 11))
            }
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
        let allNotes = (try? store.service.listNotes(includeArchived: false)) ?? []

        var byName: [String: RepoSnapshotFile.Repo] = [:]
        let result: (StudioTodo, String) = await Task.detached(priority: .userInitiated) {
            let needsStop = folder.startAccessingSecurityScopedResource()
            defer { if needsStop { folder.stopAccessingSecurityScopedResource() } }

            guard let snap = try? RepoSnapshotFile.read(fromFolder: folder) else {
                return (StudioTodo.unread(),
                        "no readable snapshot in \(folder.path) — run check-repos.sh --publish")
            }

            // memory.md lives in each project, under folders already granted for
            // scanning. Missing is normal: only one project has one so far.
            var steps: [String: MemoryRead] = [:]
            let opened = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (u, ok) in opened where ok { u.stopAccessingSecurityScopedResource() } }
            for (root, _) in opened {
                guard let kids = try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                else { continue }
                for kid in kids {
                    let name = kid.lastPathComponent
                    let m = kid.appendingPathComponent("memory.md")
                    if FileManager.default.fileExists(atPath: m.path) {
                        do {
                            let body = try String(contentsOf: m, encoding: .utf8)
                            if let step = StudioTodo.nextStep(fromMemory: body) {
                                steps[name] = .step(step)
                            } else {
                                steps[name] = .readNoStep
                            }
                        } catch {
                            steps[name] = .unreadable
                        }
                    } else {
                        steps[name] = .readNoStep
                    }
                }
            }

            let reposSet = Set(snap.repos.map(\.name))
            var aiFlags: [String: [Note]] = [:]
            for note in allNotes where note.tags.contains("todo") {
                for tag in note.tags where reposSet.contains(where: { $0.lowercased() == tag }) {
                    aiFlags[tag, default: []].append(note)
                }
            }

            let t = StudioTodo.derive(from: snap, nextSteps: steps, aiFlags: aiFlags)
            byName = Dictionary(uniqueKeysWithValues: snap.repos.map { ($0.name, $0) })
            let readCount = steps.values.filter { $0 != .unreadable }.count
            return (t, "\(t.items.count) items from \(snap.repos.count) repos · "
                     + "\(readCount) memory.md · snapshot "
                     + snap.generatedAt.formatted(.relative(presentation: .named))
                     + " · \(folder.path)")
        }.value

        todo = result.0
        sourceNote = result.1
        repos = byName
    }
}

/// "Fix with AI" for one to-do item, mirroring `AIReviewMenu`.
///
/// Same contract, deliberately: it lists the tools the user has configured and copies a
/// prompt for whichever they pick. It does not inspect another tool's config to claim a
/// live connection, and it does not act — the app is sandboxed and cannot run `Process`,
/// so it could not perform the fix even if the label implied it.
struct AITodoMenu: View {
    @EnvironmentObject var store: AppStore
    let item: StudioTodo.Item
    let repo: RepoSnapshotFile.Repo?

    // The menu closes the moment a target is picked, so without this the only
    // evidence the click did anything is on the clipboard — somewhere the user
    // has to leave the app to check. Same pattern, and deliberately the same
    // three seconds, as `CleanupMenu` in ContentView.swift.
    @State private var feedback: String?

    var body: some View {
        Menu {
            ForEach(store.availableTargets) { target in
                Button {
                    store.copyTodoPrompt(for: target, item: item, repo: repo)
                    showFeedback("Copied — paste it into \(target.displayName).")
                } label: {
                    Text(target.displayName)
                }
            }
            Divider()
            Text("Copies this next step, plus the repository state it came from, to paste into the LLM.")
                .foregroundColor(Theme.textPrimary)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text("Fix with AI…")
            }
            .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        // An overlay, not a VStack: these rows size to their content and a
        // toast that pushes layout would shift every row below it for three
        // seconds. `allowsHitTesting(false)` keeps it from eating the click
        // that reopens the menu.
        .overlay(alignment: .bottomLeading) {
            if let feedback {
                Text(feedback)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.emerald)
                    .transition(.opacity)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(y: 20)
                    .allowsHitTesting(false)
            }
        }
    }

    private func showFeedback(_ text: String) {
        withAnimation { feedback = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { feedback = nil }
        }
    }
}
