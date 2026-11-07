import SwiftUI
import UIKit
import UnliRiceCore

struct CaptureStudioView: View {
    @ObservedObject var store: CaptureStore
    let onRecordForProject: (StudioOverviewFile.Project) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var overview: StudioOverviewFile?
    @State private var notes: [Note] = []
    @State private var message: String?
    @State private var notesError: String?
    @Binding var selectedID: String?
    @State private var detail: StudioOverviewFile.Project?
    @State private var selectedNote: Note?
    private var projects: [StudioOverviewFile.Project] { overview?.projects ?? [] }
    private var selected: StudioOverviewFile.Project? { projects.first { $0.id == selectedID } }
    private var pending: [Note] { CaptureContext.pendingNotes(in: notes) }
    private var unassigned: [Note] { CaptureContext.unassignedNotes(in: notes, knownProjects: projects.map(\.projectTag)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let notesError { Text("Notes could not be refreshed. Previously loaded notes may be out of date: \(notesError)").font(.caption).foregroundStyle(.secondary) }
                if let overview {
                    Text("Published by \(overview.deviceLabel) · \(overview.generatedAt.formatted(date: .abbreviated, time: .shortened))\(overview.isStale() ? " · Older snapshot" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(overview.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                } else if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) { projectsDeck; branchesDeck }
                } else { projectsDeck; branchesDeck }
                notesDeck
            }.padding(.vertical, 4)
        }
        .background(CaptureStudioStyle.color(.background, scheme))
        .refreshable { reload() }
        .onAppear { reload() }
        .onChange(of: store.overviewRevision) { _, _ in refreshData() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in reload() }
        .sheet(item: $detail, onDismiss: reload) { project in
            NavigationStack { CaptureProjectView(store: store, project: project, projects: projects, notes: notes, reload: reload) }.modifier(CapturePrivacyCover())
        }
        .sheet(item: $selectedNote, onDismiss: reload) { note in
            NavigationStack { CaptureNoteDetail(store: store, initialNote: note, projects: projects, reload: reload) }.modifier(CapturePrivacyCover())
        }
    }

    private var projectsDeck: some View {
        StudioDeck(title: "Projects", symbol: "square.stack.3d.up.fill", accent: .garden) {
            if let project = selected {
                CaptureProjectDeck(projects: projects, selectedID: $selectedID, notes: notes,
                                   sticker: sticker, todoCount: { projectTodos($0).count },
                                   open: { detail = $0 })
                Button { onRecordForProject(project) } label: {
                    Label("Record for \(project.name)", systemImage: "mic.fill").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).studioControl().disabled(store.captureInFlight)
                Text("Next step").font(.caption.bold()).foregroundStyle(.secondary)
                Text(project.nextStep ?? "Unknown").font(.subheadline)
            } else { Text("No project overview available.").foregroundStyle(.secondary) }
        }
    }
    private var branchesDeck: some View {
        StudioDeck(title: "Branches", symbol: "point.3.connected.trianglepath.dotted", accent: .branches) {
            if let project = selected { BranchEvidenceView(project: project) }
            else { Text("Select a project to see its recorded branches.").foregroundStyle(.secondary) }
        }
    }
    private var notesDeck: some View {
        StudioDeck(title: "Notes", symbol: "note.text", accent: .notes) {
            Text("\(pending.count) pending \(pending.count == 1 ? "capture" : "captures")").font(.headline)
            if pending.isEmpty { Text("No pending captures.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(Array(pending.prefix(5))) { note in noteButton(note) }
            if pending.count > 5 {
                DisclosureGroup("More pending captures (\(pending.count - 5))") {
                    ForEach(Array(pending.dropFirst(5))) { note in noteButton(note) }
                }
            }
            DisclosureGroup("All tracked captures") {
                ForEach(notes.filter { CaptureContext.isCapture($0) && !$0.archived }.sorted { $0.updatedAt > $1.updatedAt }) { note in noteButton(note) }
            }
            Text("Unassigned").font(.subheadline.bold()).padding(.top, 4)
            if unassigned.isEmpty { Text("No unassigned pending captures.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(unassigned) { note in noteButton(note) }
        }
    }
    private func noteButton(_ note: Note) -> some View {
        Button { selectedNote = note } label: {
            HStack { Text(note.title).multilineTextAlignment(.leading); Spacer(); Image(systemName: "chevron.right") }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func sticker(_ project: StudioOverviewFile.Project) -> String {
        if !project.issues.isEmpty { return "Needs attention" }
        guard let status = project.status, !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Status unknown" }
        if !CaptureContext.pendingNotes(in: notes, project: project.projectTag).isEmpty || !projectTodos(project).isEmpty { return "Needs you" }
        return "Up to date"
    }
    private func projectTodos(_ project: StudioOverviewFile.Project) -> [Note] {
        notes.filter { !$0.archived && $0.tags.contains("todo") && $0.tags.contains { CaptureContext.normalizedProject($0) == CaptureContext.normalizedProject(project.projectTag) } }
    }
    private func reload() {
        store.sync()
        refreshData()
    }
    private func refreshData() {
        do { notes = try store.noteService.listNotes(includeArchived: false); notesError = nil }
        catch { notesError = error.localizedDescription }
        do {
            overview = try store.loadStudioOverview()
            message = overview == nil ? "Studio overview unavailable. \(store.syncStatus)" : nil
            if !projects.contains(where: { $0.id == selectedID }) { selectedID = projects.first?.id }
        } catch { overview = nil; message = "Studio overview unavailable: \(error.localizedDescription) Pending captures remain available." }
    }
}
