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
    @State private var selectedID: String?
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
            if let project = selected, let index = projects.firstIndex(where: { $0.id == project.id }) {
                ZStack {
                    ForEach(Array((0..<min(3, projects.count)).reversed()), id: \.self) { offset in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(CaptureStudioStyle.color([.cover0, .cover1, .cover2, .cover3, .cover4, .cover5, .cover6, .cover7][(index + offset) % 8], scheme))
                            .offset(x: CGFloat(offset * 5), y: CGFloat(-offset * 5))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    Button { detail = project } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "folder.fill").font(.title2)
                            Text(project.name).font(.title2.bold())
                            Text(sticker(project)).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.white.opacity(0.18), in: Capsule())
                            Text(project.status ?? "Status unknown").font(.subheadline)
                            Text("\(CaptureContext.pendingNotes(in: notes, project: project.projectTag).count) pending \(CaptureContext.pendingNotes(in: notes, project: project.projectTag).count == 1 ? "capture" : "captures") · \(projectTodos(project).count) \(projectTodos(project).count == 1 ? "to-do" : "to-dos")")
                                .font(.caption)
                        }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(20).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("studio-project-\(project.id)")
                        .accessibilityLabel("Open project \(project.name)")
                }.padding(.top, 10).padding(.trailing, 10)
                HStack {
                    Button { select(index - 1) } label: { Label("Previous project", systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 44, height: 44) }.studioControl().disabled(index == 0)
                    Spacer()
                    Text("\(index + 1) of \(projects.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { select(index + 1) } label: { Label("Next project", systemImage: "chevron.right").labelStyle(.iconOnly).frame(width: 44, height: 44) }.studioControl().disabled(index + 1 == projects.count)
                }
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
    private func select(_ index: Int) { if projects.indices.contains(index) { selectedID = projects[index].id } }
    private func reload() {
        store.sync()
        do { notes = try store.noteService.listNotes(includeArchived: false); notesError = nil }
        catch { notesError = error.localizedDescription }
        guard let folder = store.sharedFolderURL else { overview = nil; message = "No shared folder is set up. Pending captures remain available on this device."; return }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        do {
            overview = try StudioOverviewFile.read(fromFolder: folder)
            message = nil
            if !projects.contains(where: { $0.id == selectedID }) { selectedID = projects.first?.id }
        } catch { overview = nil; message = "Studio overview unavailable: \(error.localizedDescription) Pending captures remain available." }
    }
}
