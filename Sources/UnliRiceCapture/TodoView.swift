import SwiftUI
import UnliRiceCore

/// The studio's outstanding work, on the phone — to read, and to think against.
///
/// **Viewing and note taking only.** Nothing here pushes, deletes, prunes or changes a
/// repository. The phone has no repositories and no access to the Mac's folders; it is
/// reading the snapshot the Mac published, which is a photograph. Every item is derived
/// from the state that makes it true, so there is nothing to tick off — an item goes
/// away when the work is actually done.
///
/// What the phone adds over the Mac is the note: away from the desk, "what did I say I
/// would do here" is most of the value, and the useful reply is a thought rather than a
/// command. Notes are appended to one note per project, reusing `.appended` — no new
/// `EventKind`, and title immutability holds.
struct TodoView: View {
    @ObservedObject var store: CaptureStore

    @State private var todo = StudioTodo(items: [])
    @State private var status = ""
    @State private var loaded = false
    @State private var noteFor: StudioTodo.Item?
    @State private var draft = ""

    var body: some View {
        ZStack {
            Theme.bgMain.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if !loaded {
                        ProgressView().padding(.vertical, 24)
                    } else if todo.items.isEmpty {
                        card("Nothing outstanding",
                             status.isEmpty
                             ? "Every branch tip is on a remote and no project names a next step."
                             : status)
                    } else {
                        ForEach(StudioTodo.Kind.allCases, id: \.rawValue) { kind in
                            let items = todo.items.filter { $0.kind == kind }
                            if !items.isEmpty { section(kind, items) }
                        }
                    }
                }
                .padding(18)
            }
        }
        .task { load() }
        .refreshable { load() }
        .sheet(item: $noteFor) { item in noteSheet(item) }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("To do")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("From your Mac's last snapshot. Read-only — tap an item to leave a note "
                 + "about it.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textLight)
            }
        }
    }

    private func section(_ kind: StudioTodo.Kind, _ items: [StudioTodo.Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.label.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(kind == .atRisk ? .orange : Theme.textSecondary)
            ForEach(items) { item in
                Button { draft = ""; noteFor = item } label: { row(item, kind) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ item: StudioTodo.Item, _ kind: StudioTodo.Kind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.project)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text(item.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            Text(item.evidence)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.bgField, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            if kind == .atRisk { Rectangle().fill(Color.orange).frame(width: 2) }
        }
    }

    private func card(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(body).font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.bgField, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - The note

    private func noteSheet(_ item: StudioTodo.Item) -> some View {
        NavigationView {
            ZStack {
                Theme.bgMain.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.project)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ZStack(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("What about this?")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.textLight)
                                .padding(.top, 8).padding(.leading, 5)
                        }
                        TextEditor(text: $draft)
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)
                    }
                    .padding(6)
                    .background(Theme.bgField, in: RoundedRectangle(cornerRadius: 10))

                    // What the note is stamped with, shown before saving rather than
                    // discovered afterwards — a note that records only the thought is
                    // worthless in a month.
                    Text("Saved to “\(Self.noteTitle(item.project))” with the item and "
                         + "today's date. Appended, never overwritten.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { noteFor = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(item) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    /// One note per project, and the title is the key. Titles are permanent by design —
    /// there is no retitle event — so the title is a safer handle than a stored mapping,
    /// which could disagree with the corpus.
    static func noteTitle(_ project: String) -> String { "Repo: \(project)" }

    private func save(_ item: StudioTodo.Item) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        let body = "[\(item.project) · \(item.title) · \(stamp)]\n\(text)"
        store.appendToProjectNote(title: Self.noteTitle(item.project), text: body)
        noteFor = nil
        draft = ""
    }

    // MARK: - Loading

    private func load() {
        defer { loaded = true }
        guard let folder = store.sharedFolderURL else {
            status = "No shared folder set up yet — choose one in Settings."
            return
        }
        let needsStop = folder.startAccessingSecurityScopedResource()
        defer { if needsStop { folder.stopAccessingSecurityScopedResource() } }

        do {
            let snap = try RepoSnapshotFile.read(fromFolder: folder)
            todo = StudioTodo.derive(from: snap)
            status = "\(snap.repos.count) repos · "
                   + snap.generatedAt.formatted(.relative(presentation: .named))
                   + (snap.isStale() ? " · may be out of date" : "")
        } catch let e as RepoSnapshotFile.ReadError {
            todo = StudioTodo(items: [])
            status = e == .missing
                ? "Your Mac has not published a snapshot yet."
                : (e.localizedDescription)
        } catch {
            todo = StudioTodo(items: [])
            status = "The snapshot could not be read."
        }
    }
}
