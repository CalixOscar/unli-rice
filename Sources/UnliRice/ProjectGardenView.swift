import AppKit
import SwiftUI
import UnliRiceCore

struct ProjectGardenView: View {
    @EnvironmentObject private var store: AppStore
    @State private var report: ProjectGarden.Report?
    @State private var selectedProject: ProjectGarden.Project?
    @State private var searchText = ""
    @State private var showingAttentionOnly = false
    @State private var loading = true
    @State private var refreshError: String?
    @State private var refreshID = UUID()
    @State private var activeRequestID = UUID()

    private struct LoadKey: Equatable {
        let corpus: URL
        let roots: [URL]
        let notes: [Note]
        let refresh: UUID
    }

    private var loadKey: LoadKey {
        LoadKey(corpus: store.dataURL, roots: store.scanRoots, notes: store.notes, refresh: refreshID)
    }

    private var visibleProjects: [ProjectGarden.Project] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (report?.projects ?? []).filter { project in
            (!showingAttentionOnly || project.needsAttention) &&
            (query.isEmpty || [project.name, project.status, project.nextStep]
                .compactMap { $0?.lowercased() }.contains { $0.contains(query) } ||
             project.notes.contains { $0.title.lowercased().contains(query) })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let refreshError {
                    issueBanner(refreshError)
                }
                if let report, !report.issues.isEmpty {
                    DisclosureGroup("Some sources could not be fully checked (\(report.issues.count))") {
                        ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                            issueBanner(issue)
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                summary
                comparisonLegend
                controls
                content
                if let report {
                    Text("Checked \(report.scannedAt.formatted(date: .abbreviated, time: .shortened)). Saved sources carry their own dates.")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .background(Theme.bgMain)
        .task(id: loadKey) { await load() }
        .onChange(of: store.dataURL.path) { _ in
            report = nil
            selectedProject = nil
            refreshError = nil
        }
        .sheet(item: $selectedProject) { project in
            ProjectGardenDetail(project: project) {
                selectedProject = nil
                store.selectNote($0)
            }
            .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(Theme.emerald)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text("Project Garden")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your projects, where you left them, and what comes next.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 14) {
                    if store.isOn(.todo) {
                        Button("To do") { store.showTodo() }
                    }
                    Button("Manage folders") { store.showGardenFolders() }
                }
                .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Theme.accentColor)
            }
            Spacer()
            Button {
                refreshID = UUID()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .solidControl(cornerRadius: 7)
        }
    }

    private var summary: some View {
        let projects = report?.projects ?? []
        let repositories = projects.filter { $0.repository != nil }.count
        let todoIDs = Set(projects.flatMap { $0.notes.filter { $0.tags.contains { $0.caseInsensitiveCompare("todo") == .orderedSame } }.map(\.id) })
        return HStack(spacing: 10) {
            summaryTile("Projects", value: report == nil ? "—" : "\(projects.count)", icon: "square.grid.2x2")
            summaryTile("With Git details", value: report == nil ? "—" : "\(repositories)", icon: "folder")
            summaryTile("Open to-do notes", value: report == nil ? "—" : "\(todoIDs.count)", icon: "checklist")
        }
    }

    private func summaryTile(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.borderLight, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var comparisonLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Mac and remote records")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .top, spacing: 18) {
                legendItem("laptopcomputer", title: "This Mac", detail: "local branches/linked worktrees", color: Theme.accentColor)
                legendItem("cloud", title: "Recorded remote", detail: "last fetched refs", color: Theme.violet)
                legendItem("globe", title: "Remote live", detail: "Not checked", color: Theme.textSecondary)
            }
            Text("Remote records are saved on this Mac. Refresh does not contact GitHub or other remote hosts.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.borderLight, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func legendItem(_ icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Search projects, status, next steps, or note titles", text: $searchText)
                .textFieldStyle(.plain)
            Spacer()
            Picker("Filter", selection: $showingAttentionOnly) {
                Text("All").tag(false)
                Text("Needs attention").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
        .padding(10)
        .background(Theme.bgField)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var content: some View {
        if loading && report == nil {
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading notes and granted project folders…").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }.frame(maxWidth: .infinity).padding(54)
        } else if report == nil {
            emptyState(title: "Garden could not refresh", message: "Try Refresh again. Your notes and selected folders stay available in their usual places.")
        } else if visibleProjects.isEmpty {
            if report?.projects.isEmpty == true {
                emptyState(title: "Start your project garden", message: "Add a project folder in Setup › Folders. A note titled “Project: Your project” appears here without a folder, too.")
            } else {
                VStack(spacing: 10) {
                    Text("No projects match this view.").foregroundStyle(Theme.textSecondary)
                    Button("Show all projects") { searchText = ""; showingAttentionOnly = false }
                }.frame(maxWidth: .infinity).padding(36)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                ForEach(visibleProjects) { project in
                    ProjectGardenCard(project: project) { selectedProject = project }
                }
            }
        }
        if report != nil && loading {
            Text("Refreshing… last successful report remains visible.").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(message).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button("Manage project folders") { store.showGardenFolders() }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentColor)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.borderLight, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func issueBanner(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.system(size: 11.5)).foregroundStyle(Theme.brass)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brass.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func load() async {
        let key = loadKey
        let requestID = UUID()
        activeRequestID = requestID
        loading = true
        defer { if activeRequestID == requestID { loading = false } }
        let service = store.service
        let roots = store.scanRoots
        let corpusFolder = store.dataURL.deletingLastPathComponent()
        do {
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let corpusAccess = corpusFolder.startAccessingSecurityScopedResource()
                defer { if corpusAccess { corpusFolder.stopAccessingSecurityScopedResource() } }
                let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
                defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
                let notes = try service.listNotes(includeArchived: false)
                try Task.checkCancellation()
                let snapshotURL = corpusFolder.appendingPathComponent(RepoSnapshotFile.filename)
                var snapshot: RepoSnapshotFile?
                var issues: [String] = []
                if FileManager.default.fileExists(atPath: snapshotURL.path) {
                    do { snapshot = try RepoSnapshotFile.read(fromFolder: corpusFolder) }
                    catch { issues.append("Saved repository details could not be read. Available notes and folders are shown. \(error.localizedDescription)") }
                }
                let loaded = ProjectGarden.load(roots: roots, notes: notes, publishedSnapshot: snapshot)
                try Task.checkCancellation()
                return ProjectGarden.Report(projects: loaded.projects, scannedAt: loaded.scannedAt, issues: loaded.issues + issues)
            }
            let result = try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: { worker.cancel() })
            guard !Task.isCancelled, activeRequestID == requestID, loadKey == key else { return }
            report = result
            refreshError = nil
            if let selected = selectedProject {
                selectedProject = result.projects.first { $0.id == selected.id }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeRequestID == requestID, loadKey == key else { return }
            refreshError = "Refresh could not complete: \(error.localizedDescription)."
        }
    }
}

private struct ProjectGardenCard: View {
    let project: ProjectGarden.Project
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: project.needsAttention ? "leaf.fill" : "leaf")
                        .foregroundStyle(project.needsAttention ? Theme.brass : Theme.emerald)
                    Text(project.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    if project.needsAttention { Text("Needs attention").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.brass) }
                }
                if let folder = project.folderURL {
                    Text(folder.path).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle).help(folder.path)
                } else {
                    Text(project.repository == nil ? "From your notes" : "From a saved repository snapshot")
                        .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                }
                Text(project.status ?? "No recorded status yet.").font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                sourceLine(project.statusSource, date: project.statusDate)
                if let next = project.nextStep {
                    Text("Next: \(next)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    sourceLine(project.nextStepSource, date: nil)
                } else {
                    Text("No next step recorded.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Divider().opacity(0.2)
                HStack(spacing: 12) {
                    Label("\(project.notes.count) notes", systemImage: "note.text")
                    Label("\(project.todoCount) to-do · \(project.reviewCount) review", systemImage: "flag")
                }.font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                RepositoryComparison(repository: project.repository, compact: true)
                if let issue = project.issues.first {
                    Label(issue, systemImage: "info.circle").font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                Text("View project →").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accentColor)
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgCard).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    private func sourceLine(_ source: String?, date: Date?) -> some View {
        Text([source, date.map { $0.formatted(date: .abbreviated, time: .shortened) }].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
    }

}

private struct ProjectGardenDetail: View {
    let project: ProjectGarden.Project
    let openNote: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(project.name).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let folder = project.folderURL {
                        Text(folder.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                        Button("Reveal folder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                            .buttonStyle(.plain).foregroundStyle(Theme.accentColor)
                    }
                    detailField("Recorded status", value: project.status ?? "None recorded", source: project.statusSource, date: project.statusDate)
                    detailField("Next step", value: project.nextStep ?? "None recorded", source: project.nextStepSource, date: nil)
                    RepositoryComparison(repository: project.repository, compact: false)
                    ForEach(Array(project.issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    Divider()
                    Text("RELATED NOTES (\(project.notes.count))").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                    if project.notes.isEmpty {
                        Text("No related notes yet. Notes whose tags or recorded source match this project appear here.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(project.notes) { note in
                        Button { openNote(note.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                Text("\(note.creator == "ingest" ? "imported note" : "recorded note") · updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(9).background(Theme.bgField).clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24).frame(width: 620, height: 580).background(Theme.bgMain)
    }

    private func detailField(_ title: String, value: String, source: String?, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 13)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text([source, date.map { $0.formatted(date: .abbreviated, time: .shortened) }].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct RepositoryComparison: View {
    let repository: ProjectGarden.Repository?
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 10) {
            if let repository {
                localLane(repository)
                remoteLane(repository)
                comparisonSection(repository)
                Text(repository.fromPublishedSnapshot ? "Saved snapshot · \(repository.observedAt.formatted(date: .abbreviated, time: .shortened))" : "Local scan · \(repository.observedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: compact ? 9 : 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                if repository.differentTipCount != nil {
                    Text("Remote records may be older")
                        .font(.system(size: compact ? 9 : 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "laptopcomputer.and.arrow.down")
                    Text("Local and remote details unavailable")
                }
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func localLane(_ repository: ProjectGarden.Repository) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "laptopcomputer").foregroundStyle(Theme.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(repository.fromPublishedSnapshot ? "Mac snapshot" : "On this Mac")
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(localSummary(repository))
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(compact ? 2 : nil)
            }
        }
    }

    private func remoteLane(_ repository: ProjectGarden.Repository) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "cloud").foregroundStyle(Theme.violet)
            Text(repository.differentTipCount == nil ? "No remote records available" : "Recorded remote")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func localSummary(_ repository: ProjectGarden.Repository) -> String {
        let branchText = "\(max(repository.branchCount, 0)) branches"
        let worktreeText = "\(max(repository.worktreeCount, 0)) linked worktrees"
        if let currentBranch = repository.currentBranch, !currentBranch.isEmpty {
            return "\(currentBranch) · \(branchText) · \(worktreeText)"
        }
        return "\(branchText) · \(worktreeText)"
    }

    @ViewBuilder
    private func comparisonSection(_ repository: ProjectGarden.Repository) -> some View {
        let branchCount = max(repository.branchCount, 0)
        if let rawDifferent = repository.differentTipCount {
            let different = min(max(rawDifferent, 0), branchCount)
            let matching = branchCount - different
            VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                if repository.branchCount < 0 || rawDifferent < 0 || rawDifferent > branchCount {
                    Text("Branch tip comparison unavailable")
                        .font(.system(size: compact ? 9 : 11))
                        .foregroundStyle(Theme.textSecondary)
                    neutralTrack
                } else if branchCount == 0 {
                    Text("No local branch tips to compare")
                        .font(.system(size: compact ? 9 : 11))
                        .foregroundStyle(Theme.textSecondary)
                    neutralTrack
                } else {
                    comparisonBar(matching: matching, different: different, total: branchCount)
                    VStack(alignment: .leading, spacing: compact ? 3 : 7) {
                        comparisonLabel("Matching tips", count: matching, caption: "Same commit ID in recorded remotes", color: Theme.emerald)
                        comparisonLabel("Different tips", count: different, caption: "Different from recorded remotes", color: Theme.violet)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Remote comparison unknown")
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(Theme.textSecondary)
                neutralTrack
            }
        }
    }

    private var neutralTrack: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Theme.textLight, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: compact ? 7 : 10)
            .accessibilityLabel("Neutral branch tip comparison track")
            .accessibilityValue("Comparison unavailable")
    }

    private func comparisonBar(matching: Int, different: Int, total: Int) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Theme.emerald.frame(width: proxy.size.width * CGFloat(matching) / CGFloat(total))
                Theme.violet.frame(width: proxy.size.width * CGFloat(different) / CGFloat(total))
            }
            .clipShape(Capsule())
        }
        .frame(height: compact ? 7 : 10)
        .background(Theme.borderLight, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Branch tip comparison")
        .accessibilityValue("\(matching) Matching tips, \(different) Different tips")
    }

    private func comparisonLabel(_ title: String, count: Int, caption: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6).padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(title) · \(count)")
                    .font(.system(size: compact ? 9 : 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !compact {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
