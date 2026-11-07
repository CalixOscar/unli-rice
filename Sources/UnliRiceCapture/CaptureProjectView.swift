import SwiftUI
import UIKit
import UnliRiceCore

struct BranchEvidenceView: View {
    let project: StudioOverviewFile.Project
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Observed \(project.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            Text("Live remote not checked").font(.caption.bold())
            if let repo = project.repository {
                Text("On this Mac: \(repo.branches.count) local branches · \(repo.currentBranch ?? (repo.detachedHead ? "Detached HEAD" : "Current branch unknown"))")
                Text("Recorded remote: \(repo.remoteBranchCount) branches").font(.subheadline)
                if repo.remoteBranchCount == 0 { Text("No remote evidence recorded.").font(.caption).foregroundStyle(.secondary) }
                ForEach(repo.branches, id: \.name) { branch in
                    VStack(alignment: .leading) {
                        Text(branch.name).font(.subheadline.bold())
                        Text(repo.remoteBranchCount == 0 ? "No remote evidence recorded" : (branch.tipOnRemote ? "Tip found in recorded remotes" : "Tip not found in recorded remotes"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else { Text("Branch evidence unavailable.").foregroundStyle(.secondary) }
        }
    }
}

struct CaptureProjectView: View {
    @ObservedObject var store: CaptureStore
    let project: StudioOverviewFile.Project
    let projects: [StudioOverviewFile.Project]
    @State private var notes: [Note]
    let reload: () -> Void
    init(store: CaptureStore, project: StudioOverviewFile.Project, projects: [StudioOverviewFile.Project], notes: [Note], reload: @escaping () -> Void) {
        self.store = store; self.project = project; self.projects = projects
        self._notes = State(initialValue: notes); self.reload = reload
    }
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNote: Note?
    @State private var notesError: String?
    private var captures: [Note] { CaptureContext.pendingNotes(in: notes, project: project.projectTag) }
    private var todos: [Note] { notes.filter { !$0.archived && $0.tags.contains("todo") && $0.tags.contains { CaptureContext.normalizedProject($0) == CaptureContext.normalizedProject(project.projectTag) } } }
    var body: some View {
        List {
            if let notesError { Text("Notes may be out of date: \(notesError)").font(.caption) }
            Section("Status & next step") {
                Text(project.status ?? "Status unknown")
                if let date = project.statusDate { Text("Status dated \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                Text(project.nextStep ?? "Next step unknown")
                Text("Observed \(project.observedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                ForEach(project.issues, id: \.self) { Text($0).font(.caption) }
            }
            Section("Captures") {
                if captures.isEmpty { Text("No pending captures.").foregroundStyle(.secondary) }
                ForEach(captures) { noteRow($0) }
            }
            Section("To-dos") {
                if todos.isEmpty { Text("No to-dos.").foregroundStyle(.secondary) }
                ForEach(todos) { noteRow($0) }
            }
            Section("Branches") { BranchEvidenceView(project: project) }
            Section("Build stages") {
                ForEach(["idea", "intent", "spec", "agents", "premortem", "build", "postmortem"], id: \.self) { stage in
                    VStack(alignment: .leading) {
                        Text("\(stage.capitalized): \(project.stages[stage]?.state ?? "Unknown")")
                        if let reason = project.stages[stage]?.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { refreshNotes() }
        .modifier(CapturePrivacyCover())
        .sheet(item: $selectedNote, onDismiss: { refreshNotes(); reload() }) { note in
            NavigationStack { CaptureNoteDetail(store: store, initialNote: note, projects: projects, reload: reload) }.modifier(CapturePrivacyCover())
        }
    }
    private func refreshNotes() {
        do { notes = try store.noteService.listNotes(includeArchived: false); notesError = nil }
        catch { notesError = error.localizedDescription }
    }
    private func noteRow(_ note: Note) -> some View {
        Button { selectedNote = note } label: { Text(note.title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
    }
}

struct CaptureNoteDetail: View {
    @ObservedObject var store: CaptureStore
    let initialNote: Note
    let projects: [StudioOverviewFile.Project]
    let reload: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note?
    @State private var projectID = ""
    @State private var error: String?
    private var current: Note { note ?? initialNote }
    private var matching: [StudioOverviewFile.Project] { projects.filter { project in current.tags.contains { CaptureContext.normalizedProject($0) == CaptureContext.normalizedProject(project.projectTag) } } }
    private var selectedProject: StudioOverviewFile.Project? { projects.first { $0.id == projectID } }
    private var handoff: String { CaptureContext.handoff(note: current, project: matching.count == 1 ? matching.first?.projectTag : nil, observedAt: matching.count == 1 ? matching.first?.observedAt : nil) }
    var body: some View {
        Form {
            Section("Capture") {
                Text(current.title).font(.headline)
                Text(current.body).textSelection(.enabled)
                Text(CaptureContext.isPending(current) ? "Pending" : (current.tags.contains(CaptureContext.deferredTag) ? "Set aside" : "Not pending"))
                Text(matching.count > 1 ? "Project association is ambiguous: \(matching.map(\.name).joined(separator: ", "))" : (matching.first?.name ?? "Unassigned"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(store.syncStatus).font(.caption).foregroundStyle(.secondary)
                Text(store.receivedCaptureIDs.contains(current.id) ? "Mac receipt confirmed" : "Mac receipt not confirmed").font(.caption)
            }
            Section("Act with AI") {
                ShareLink(item: handoff) { Label("Share handoff", systemImage: "square.and.arrow.up") }
                Button("Copy handoff") { UIPasteboard.general.string = handoff }
            }
            Section("Project") {
                Picker("Choose project", selection: $projectID) {
                    Text("Choose a project").tag("")
                    ForEach(projects) { Text($0.name).tag($0.id) }
                }
                Button("Assign project") {
                    guard let project = selectedProject else { return }
                    perform { _ = try store.noteService.tagNote(id: current.id, tag: project.projectTag, source: "human") }
                }.disabled(selectedProject == nil)
                Button("Add to to-dos") {
                    guard let project = selectedProject else { return }
                    perform { try CaptureContext.addToTodo(id: current.id, project: project.projectTag, service: store.noteService, source: "human") }
                }.disabled(selectedProject == nil)
            }
            Section("Capture state") {
                if !CaptureContext.isCapture(current) {
                    Button("Track this capture") { perform { try CaptureContext.track(id: current.id, service: store.noteService, source: "human") } }
                } else if CaptureContext.isPending(current) {
                    Button("Set aside") { perform { try CaptureContext.setPending(id: current.id, pending: false, service: store.noteService, source: "human") } }
                } else {
                    Button("Restore to pending") { perform { try CaptureContext.setPending(id: current.id, pending: true, service: store.noteService, source: "human") } }
                }
            }
        }
        .onAppear { if matching.count == 1 { projectID = matching[0].id } }
        .modifier(CapturePrivacyCover())
        .navigationTitle("Capture")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .alert("Could not update capture", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); store.sync(); note = try store.noteService.getNote(id: current.id); reload() }
        catch { self.error = error.localizedDescription; store.sync(); note = try? store.noteService.getNote(id: current.id); reload() }
    }
}
