import SwiftUI
import UnliRiceCore

/// What is outstanding across the studio, in the order it would hurt to ignore.
///
/// **Repo and memory.md items cannot be ticked off**, by design. They are derived
/// from the state that makes them true, so each disappears when the work is actually
/// done rather than when someone remembers to mark it. A checklist you tick is a second
/// source of truth, and this codebase has already paid for notes that disagree with the
/// repo. Items flagged by AI are stored notes tagged `todo`, where Done archives the note.
///
/// It reads repository snapshots, each project's `memory.md` `**Next step:**`, and
/// notes tagged `todo`. Git tells you what is at risk; the note tells you what you
/// meant to do or what an AI flagged.
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
        .task(id: store.todoRefreshToken) { await load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To do")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("What's worth doing across your projects. Most items are worked out from your "
                 + "project folders and disappear by themselves once the work is done, so they can't "
                 + "go out of date. Items an AI assistant suggested have a Done button — tick them "
                 + "off when they're finished.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Always visible, not only on failure. The equivalent line on the Repos
            // pane is what turned "why is this empty" from an afternoon of elimination
            // into one launch.
            // The technical detail (paths, counts) stays one hover away for whoever is
            // diagnosing an empty pane; the line itself is written for the founder.
            if !sourceNote.isEmpty {
                HStack(spacing: 8) {
                    Text(checkedLine)
                    if let gap = todo.coverage.gapSummary {
                        Text("·")
                        Text(gap)
                            .foregroundStyle(Theme.brass)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .help(sourceNote)
            }
        }
    }

    /// "Checked 8 projects 2 hours ago" — when the list was last worked out, in words.
    private var checkedLine: String {
        guard todo.coverage.snapshotRead else {
            return "Add your code folders in Repos to also see work that isn't backed up"
        }
        let n = todo.coverage.repositories.count
        let projects = n == 1 ? "1 project" : "\(n) projects"
        guard let at = todo.coverage.generatedAt else { return "Checked \(projects)" }
        return "Checked \(projects) \(at.formatted(.relative(presentation: .named)))"
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
            return "When an AI assistant spots something for later, it shows up here, and on the "
                 + "To do widget. To also see work that isn't backed up yet, add your code folders "
                 + "in Repos."
        case .emptySnapshot:
            return "The folders you added don't hold any projects Unli Rice can read. You can "
                 + "change them in Repos."
        case .nothingOutstanding:
            let asOf = todo.coverage.generatedAt.map { " as of \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "All your work is backed up, and no project has a next step written down\(asOf)."
        case .qualified(let message):
            let asOf = todo.coverage.generatedAt.map { " as of \($0.formatted(.relative(presentation: .named)))" } ?? ""
            return "Everything Unli Rice could check is backed up, but \(message)\(asOf)."
        }
    }

    private func section(_ kind: StudioTodo.Kind, _ items: [StudioTodo.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(kind.label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(kind == .atRisk ? .orange : Theme.textSecondary)
                Text(kind.blurb)
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
            Text(evidenceLine(for: item, kind: kind))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // A next step is written for the next AI session and can run to a paragraph;
            // the row shows its first sentence and keeps the rest one click away.
            if let detail = item.detail {
                DisclosureGroup("Details") {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.system(size: 11))
            }
            // Only on declared next steps. At-risk and clutter items already carry an
            // exact command, and a menu on every row adds a decision to every line —
            // which teaches you to ignore it on the rows where the command was faster.
            if kind == .declared {
                AITodoMenu(item: item, repo: repos[item.project])
                    .padding(.top, 2)
            }
            if kind == .aiFlagged, let noteID = item.noteID, let note = store.note(id: noteID) {
                // Fix with AI here too: an item's own text tells the founder "an AI can do
                // this — use Fix with AI", so the button has to be where they read that.
                HStack(spacing: 14) {
                    Button("Done") { store.archive(note, reason: "done"); Task { await load() } }
                        .font(.system(size: 11))
                    Button("Open") { store.closeAllPanes(); store.selectNote(note.id) }
                        .font(.system(size: 11))
                    NoteTodoPromptMenu(itemNote: note)
                }
                .padding(.top, 2)
            }
            if let fix = item.fix {
                // Shown, never run. This pane reports; the founder acts.
                Text("To fix it, ask your AI assistant to run this, or paste it into Terminal:")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
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

    private func evidenceLine(for item: StudioTodo.Item, kind: StudioTodo.Kind) -> String {
        if kind == .aiFlagged, let noteID = item.noteID, let note = store.note(id: noteID) {
            let projectTags = note.tags.filter { $0 != "todo" && $0 != "handoff" }
            let projects = projectTags.map { tag in
                repos.values.first(where: { $0.name.lowercased() == tag.lowercased() })?.name ?? tag
            }
            return TodoWording.subtitle(creator: note.creator, createdAt: note.createdAt, projects: projects)
        }
        return item.evidence
    }

    // MARK: - Loading

    private func load() async {
        // Only the first load shows a spinner. Later ones — the app becoming active, the
        // widget ticking something off — refresh in place instead of flashing the pane.
        if !loaded { loading = true }
        defer { loading = false; loaded = true }

        let folder = store.dataURL.deletingLastPathComponent()
        let roots = store.scanRoots
        let allNotes = (try? store.service.listNotes(includeArchived: false)) ?? []

        var byName: [String: RepoSnapshotFile.Repo] = [:]
        let result: (StudioTodo, String) = await Task.detached(priority: .userInitiated) {
            let needsStop = folder.startAccessingSecurityScopedResource()
            defer { if needsStop { folder.stopAccessingSecurityScopedResource() } }
            let opened = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (u, ok) in opened where ok { u.stopAccessingSecurityScopedResource() } }

            // The studio publishes repos.json, with ancestry, from a script. No customer
            // has that script, so without it the app scans the folders granted in Repos
            // itself (refs only: "saved only on this Mac", not ahead/behind).
            let published = try? RepoSnapshotFile.read(fromFolder: folder)
            var found = published
            if found == nil, !opened.isEmpty {
                let scanner = GitRepoScanner()
                var scans: [GitRepoScanner.Snapshot] = []
                for (root, _) in opened {
                    if let one = try? scanner.scan(repositoryAt: root) {
                        scans.append(one)
                    } else {
                        scans.append(contentsOf: scanner.scanAll(in: root))
                    }
                }
                if !scans.isEmpty { found = RepoSnapshotFile(scans: scans, deviceLabel: "this Mac") }
            }
            // AI to-dos show whatever else is missing: they are the part of this list that
            // every customer has, and the widget already shows them all (D9).
            guard let snap = found else {
                let t = StudioTodo.unread()
                    .adding(StudioTodo.unmatchedAIItems(from: allNotes, repoNames: []))
                return (t, "no project list, and no folders added in Repos · \(folder.path)")
            }

            // memory.md lives in each project, under folders already granted for
            // scanning. Missing is normal: only one project has one so far.
            var steps: [String: MemoryRead] = [:]
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
            let aiFlags = StudioTodo.aiFlags(from: allNotes, repoNames: reposSet)

            let t = StudioTodo.derive(from: snap, nextSteps: steps, aiFlags: aiFlags)
                .adding(StudioTodo.unmatchedAIItems(from: allNotes, repoNames: reposSet))
            byName = Dictionary(snap.repos.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            let readCount = steps.values.filter { $0 != .unreadable }.count
            return (t, "\(t.items.count) items from \(snap.repos.count) repos · "
                     + "\(readCount) memory.md · "
                     + (published == nil ? "scanned in the app" : "snapshot "
                        + snap.generatedAt.formatted(.relative(presentation: .named)))
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
            Text("Copies instructions for this step, and where the project stands, to paste into your AI assistant.")
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

/// "Fix with AI…" on a to-do or handoff note (B6). Reached by tapping a widget row, which
/// opens the item's handoff: the copy happens here, on a click inside the app, never from
/// a link (D10). Same targets and the same three-second confirmation as `AITodoMenu`.
struct NoteTodoPromptMenu: View {
    @EnvironmentObject var store: AppStore
    let itemNote: Note

    @State private var feedback: String?

    var body: some View {
        Menu {
            ForEach(store.availableTargets) { target in
                Button {
                    store.copyTodoPrompt(for: target, itemNote: itemNote)
                    showFeedback("Copied — paste it into \(target.displayName).")
                } label: {
                    Text(target.displayName)
                }
            }
            Divider()
            Text("Copies instructions for this to-do, and the notes it came from, to paste into your AI assistant.")
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
        .overlay(alignment: .bottomTrailing) {
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
