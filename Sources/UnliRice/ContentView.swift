import UnliRiceCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainColumn
            Divider()
            AutonomyPanel()
                .frame(width: 260)
        }
        .background(Theme.background)
        .onAppear { store.reload() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("UNLI RICE")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.brass)
                Text("AI Notes & Memory")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkDim)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 18)

            sidebarRow("All Notes", active: store.selectedNoteID == nil && !store.showingArchived) {
                store.selectNote(nil)
                store.showAllNotes()
            }
            sidebarRow(
                "Review Queue",
                active: store.selectedNoteID == nil && store.showingReviewQueue,
                badge: store.pending.count
            ) {
                store.selectNote(nil)
                store.showReviewQueue()
            }
            sidebarRow(
                "Archived",
                active: store.selectedNoteID == nil && store.showingArchived,
                badge: store.archivedNotes.count
            ) {
                store.selectNote(nil)
                store.showArchived()
            }
            sidebarRow(
                "Assistant",
                active: store.selectedNoteID == nil && store.showingAssistant
            ) {
                store.selectNote(nil)
                store.showAssistant()
            }
            Spacer()

            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button("as \(format.displayName)…") {
                        store.exportNotes(as: format)
                    }
                }
            } label: {
                Text("Export Notes…")
                    .font(.system(size: 11.5))
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(width: 190, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel)
    }

    private func sidebarRow(_ title: String, active: Bool = false, badge: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12.5))
                Spacer()
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.brass)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? Theme.accentSoft : Color.clear)
            .foregroundStyle(active ? Theme.accent : Theme.inkDim)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private var mainColumn: some View {
        Group {
            if let note = store.selectedNote {
                NoteDetailView(note: note)
            } else if store.showingAssistant {
                AssistantView()
            } else if store.showingReviewQueue {
                ReviewQueueView()
            } else {
                noteListColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var noteListColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(store.showingArchived ? "Archived Notes" : "All Notes")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                let total = store.showingArchived ? store.archivedNotes.count : store.notes.count
                Text("\(total) note\(total == 1 ? "" : "s") total · append-only")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }

            if !store.showingArchived {
                PromptRow()
            }

            if let error = store.errorMessage {
                Text("Couldn't read the event log: \(error)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.crit)
            } else if store.visibleNotes.isEmpty {
                let emptyMessage = store.showingArchived
                    ? "Nothing archived."
                    : "No notes yet — add one below to get started."
                Text(store.visibleCount == 0 ? " " : emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkDim)
                    .padding(.vertical, 12)
            } else {
                NoteList(notes: store.visibleNotes)
            }

            Text(store.statusMessage)
                .font(.system(size: 11.5))
                .italic()
                .foregroundStyle(Theme.inkDim)

            Spacer(minLength: 0)
            if !store.showingArchived {
                NewNoteRow()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The chat panel. Everything here is read-only with respect to the event
/// log — the assistant answers questions and drafts suggestions, and nothing
/// in this view (or `AppStore+Chat.swift` behind it) can tag, archive, merge,
/// or resolve anything. See `JanitorChat` for why that's structural, not a
/// promise: the model's output is a `String`, full stop.
private struct AssistantView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Assistant")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(store.chatEngineStatus.label)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }

            Text("""
            Runs a small model on your own machine — advisory only. It can \
            describe and suggest, but nothing it says changes a note; every \
            real change still goes through Accept/Reject or the note editor \
            yourself.
            """)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkDim)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.chatHistory.isEmpty {
                            Text("Ask about your notes, or what's pending in the review queue.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkDim)
                                .padding(.top, 20)
                        }
                        ForEach(store.chatHistory) { turn in
                            ChatTurnView(turn: turn)
                        }
                        if store.chatBusy {
                            Text("thinking…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.inkDim)
                                .id("bottom")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: store.chatHistory.count) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            HStack(spacing: 8) {
                TextField("Ask a question…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(9)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    .focused($inputFocused)
                    .onSubmit(send)
                Button("Ask", action: send)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .foregroundStyle(Color.white)
                    .background(store.chatBusy ? Theme.inkDim : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .disabled(store.chatBusy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { inputFocused = true }
    }

    private func send() {
        let question = draft
        draft = ""
        Task { await store.askAssistant(question) }
    }
}

private struct ChatTurnView: View {
    let turn: ChatTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(turn.question)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(turn.answer)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The review queue, full width in the main column. Used to live squeezed into
/// the 260pt right-hand panel alongside the autonomy slider, which had no room
/// for a note's full title next to a "Keep this one" button without
/// truncating one of them — see `ReviewClusterCard`.
private struct ReviewQueueView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review Queue")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(store.pending.count) item\(store.pending.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }

            // Answers "why am I seeing this at all" before the cards do — a
            // person shouldn't have to infer that from the presence of
            // action buttons.
            Text("A background helper (Preview/Run now, in the panel on the right) noticed something in each of these and wants your OK — it never changes a note by itself. Nothing below is deleted by any button; the closest thing is Archive, which is always reversible.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)

            if store.pending.isEmpty {
                Text("Nothing flagged right now.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkDim)
                    .padding(.top, 12)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Grouped, not one row per flag: a pile of five
                        // mutually-similar notes is one decision, not five.
                        // See ReviewCluster.
                        ForEach(store.pendingClusters) { cluster in
                            ReviewClusterCard(cluster: cluster)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PromptRow: View {
    @EnvironmentObject var store: AppStore
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            chip("Latest updated") { store.showLatest() }
            chip("Last 5 updated") { store.showLast(5) }
            chip("Last 10 updated") { store.showLast(10) }
            chip("Last 15 updated") { store.showLast(15) }
            chip("What's waiting on me?") {
                store.selectNote(nil)
                store.showReviewQueue()
            }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ink)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }
}

/// One row per note. Tapping a row opens `NoteDetailView` — the only place a
/// note's body, tags, links, and review flags are visible; the list itself
/// stays a title-only index, same as before.
private struct NoteList: View {
    @EnvironmentObject var store: AppStore
    let notes: [Note]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(notes) { note in
                Button(action: { store.selectNote(note.id) }) {
                    HStack {
                        HStack(spacing: 8) {
                            Text((note.sources.sorted().first ?? "—"))
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .foregroundStyle(Theme.brass)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.brass, lineWidth: 1))
                            Text(note.title)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        Spacer()
                        if note.flags.contains(where: { !$0.resolved }) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.brass)
                        }
                        Text(note.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.inkDim)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.panel)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
    }
}

/// Everything below the text fields is advisory: reusing the janitor's own
/// rules (`DraftAdvisor`) but run before the note exists, so a duplicate or a
/// missing tag is caught at the moment it's easiest to avoid. Nothing here is
/// pre-selected — every tag and every link is a chip you tap on, not
/// something applied unless you asked for it.
private struct NewNoteRow: View {
    @EnvironmentObject var store: AppStore
    @State private var title = ""
    @State private var noteBody = ""
    @State private var selectedTags: Set<String> = []
    @State private var selectedLinks: Set<UUID> = []

    private var suggestions: DraftSuggestions {
        store.draftSuggestions(title: title, body: noteBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.5)
            TextField("New note title…", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(7)
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))

            ZStack(alignment: .topLeading) {
                if noteBody.isEmpty {
                    Text("What do you want to remember? (⌘⏎ to save)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkDim)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $noteBody)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 64, maxHeight: 120)
                    .padding(4)
            }
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))

            if let duplicate = suggestions.possibleDuplicate {
                HStack(spacing: 8) {
                    Text("This looks like it might be the same as \"\(duplicate.title)\".")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Add to that note instead") { addToExisting(duplicate.id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
                .padding(8)
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.brass, lineWidth: 1))
            }

            if !suggestions.suggestedTags.isEmpty {
                chipRow("Tag it:") {
                    ForEach(suggestions.suggestedTags, id: \.self) { tag in
                        chip(tag, selected: selectedTags.contains(tag)) {
                            toggle(tag, in: &selectedTags)
                        }
                    }
                }
            }

            if !suggestions.relatedNotes.isEmpty {
                chipRow("Might be related — link to it:") {
                    ForEach(suggestions.relatedNotes) { related in
                        chip(related.title, selected: selectedLinks.contains(related.id)) {
                            toggle(related.id, in: &selectedLinks)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Add", action: add)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(Color.white)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func chipRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
            HStack(spacing: 6) { content() }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(selected ? Color.white : Theme.ink)
        .background(selected ? Theme.accent : Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Theme.border, lineWidth: selected ? 0 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    /// Skips creating a new note entirely — the draft's own text is folded
    /// into the existing one instead. See `AppStore.appendDraft(_:toExisting:)`.
    private func addToExisting(_ id: UUID) {
        let text = noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : noteBody
        guard let updated = store.appendDraft(text, toExisting: id) else { return }
        reset()
        store.selectNote(updated.id)
    }

    private func add() {
        // Intersected against the *current* suggestions rather than trusted
        // outright — if the text changed after a tag or link was selected and
        // that suggestion silently stopped applying, the stale selection
        // shouldn't still land on the note with no chip ever having shown it.
        let tagsToApply = selectedTags.intersection(suggestions.suggestedTags)
        let linksToApply = suggestions.relatedNotes.filter { selectedLinks.contains($0.id) }

        var finalBody = noteBody
        if !linksToApply.isEmpty {
            let links = linksToApply.map { "[[\($0.title)]]" }.joined(separator: ", ")
            finalBody += finalBody.isEmpty ? "See also: \(links)" : "\n\nSee also: \(links)"
        }

        guard let created = store.createNote(title: title, body: finalBody) else { return }
        for tag in tagsToApply {
            store.addTag(tag, to: created)
        }
        reset()
        store.selectNote(created.id)
    }

    private func reset() {
        title = ""
        noteBody = ""
        selectedTags = []
        selectedLinks = []
    }
}

/// The only place a note's full body is readable, appendable to, taggable, or
/// archivable. Replaces the list rather than splitting the column with it —
/// one thing on screen at a time, same principle the rest of the window uses.
private struct NoteDetailView: View {
    @EnvironmentObject var store: AppStore
    let note: Note
    @State private var draftAppend = ""
    @State private var draftTag = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                backRow
                header
                bodyText
                tagsSection
                linksSection
                flagsSection
                appendSection
            }
            .padding(20)
        }
    }

    private var backRow: some View {
        Button(action: { store.selectNote(nil) }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text(store.showingArchived ? "Archived Notes" : "All Notes")
            }
            .font(.system(size: 11.5, design: .monospaced))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.inkDim)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.title)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if note.archived {
                    Button("Unarchive") { store.unarchive(note) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                } else {
                    Button("Archive") { store.archive(note) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.crit)
                }
            }
            Text("created \(note.createdAt.formatted(.relative(presentation: .named))) · updated \(note.updatedAt.formatted(.relative(presentation: .named))) · sources: \(note.sources.sorted().joined(separator: ", "))")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
        }
    }

    private var bodyText: some View {
        Text(note.body.isEmpty ? "(empty — nothing written yet)" : note.body)
            .font(.system(size: 13))
            .foregroundStyle(note.body.isEmpty ? Theme.inkDim : Theme.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Tags")
            if !note.tags.isEmpty {
                let columns = [GridItem(.adaptive(minimum: 70), spacing: 6, alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(note.tags.sorted(), id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            Button(action: { store.removeTag(tag, from: note) }) {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(Theme.accent)
                        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Theme.accent, lineWidth: 1))
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("add tag…", text: $draftTag)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(6)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    .frame(maxWidth: 140)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
                    .disabled(draftTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag() {
        store.addTag(draftTag, to: note)
        draftTag = ""
    }

    @ViewBuilder
    private var linksSection: some View {
        if !note.outboundLinks.isEmpty || !note.danglingLinks.isEmpty || !note.backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Links")
                ForEach(note.outboundLinks.sorted(by: titleOrder), id: \.self) { id in
                    linkRow(to: id)
                }
                ForEach(note.danglingLinks.sorted(), id: \.self) { target in
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                        Text("[[\(target)]] — no note with that title yet")
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
                }
                if !note.backlinks.isEmpty {
                    Text("LINKED FROM")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                        .padding(.top, 4)
                    ForEach(note.backlinks.sorted(by: titleOrder), id: \.self) { id in
                        linkRow(to: id)
                    }
                }
            }
        }
    }

    private func titleOrder(_ a: UUID, _ b: UUID) -> Bool {
        (store.note(id: a)?.title ?? "") < (store.note(id: b)?.title ?? "")
    }

    private func linkRow(to id: UUID) -> some View {
        Button(action: { store.selectNote(id) }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right")
                Text(store.note(id: id)?.title ?? "Unknown note")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.accent)
    }

    @ViewBuilder
    private var flagsSection: some View {
        let openFlags = note.flags.filter { !$0.resolved }
        if !openFlags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Pending review")
                ForEach(openFlags, id: \.id) { flag in
                    ReviewQueueRow(note: note, flag: flag)
                }
            }
        }
    }

    private var appendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Add to this note")
            ZStack(alignment: .topLeading) {
                if draftAppend.isEmpty {
                    Text("Append more, any time — this is what makes it a memory rather than a one-shot note. Try [[Another Note Title]] to link.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draftAppend)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 56, maxHeight: 100)
                    .padding(4)
            }
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            HStack {
                Spacer()
                Button("Append", action: appendText)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(Color.white)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .disabled(draftAppend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func appendText() {
        store.append(to: note, text: draftAppend)
        draftAppend = ""
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.inkDim)
    }
}

private struct AutonomyPanel: View {
    @EnvironmentObject var store: AppStore

    private let labels = ["Eco", "Balanced", "Aggressive"]
    private let descriptions = [
        "Only cosmetic, reversible actions run, and only while plugged in and idle. No merge/split proposals.",
        "Cosmetic actions run automatically. The janitor also scans for possible merges/splits and queues proposals — nothing structural applies without your tap.",
        "Janitor looks more often and proposes more eagerly. Still queues every structural change — this setting never grants auto-apply."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                header("Agent autonomy")
                Slider(value: Binding(
                    get: { Double(store.autonomyLevel) },
                    set: { store.autonomyLevel = Int($0.rounded()) }
                ), in: 0...2, step: 1)
                .tint(Theme.accent)

                HStack {
                    ForEach(labels, id: \.self) { label in
                        Text(label.uppercased())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.inkDim)
                        if label != labels.last { Spacer() }
                    }
                }

                Text(descriptions[store.autonomyLevel])
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkDim)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.accent).frame(width: 2)
                    }
                    .padding(.leading, 8)

                JanitorControls()
            }

            // The review cards themselves live full-width in the main column
            // now (ReviewQueueView) — this narrow panel doesn't have room for
            // a note's full title next to a "Keep this one" button without
            // truncating one of them. This is just the pointer to it.
            Button(action: { store.selectNote(nil); store.showReviewQueue() }) {
                HStack {
                    header("Review queue")
                    Spacer()
                    if !store.pending.isEmpty {
                        Text("\(store.pending.count) pending →")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.brass)
                    } else {
                        Text("nothing waiting")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkDim)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Every structural action requires your approval. No delete method exists.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panel)
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.inkDim)
    }
}

/// The janitor's only trigger. There is no scheduler behind this — if you don't
/// press one of these, the janitor does not run.
///
/// "Preview" comes first and is styled as the primary action on purpose. The
/// janitor's contract is that you can always see what it would do before it does
/// anything, and a UI where "Run" is the obvious button quietly weakens that.
private struct JanitorControls: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                button("Preview", color: Theme.accent) {
                    Task { await store.previewJanitor() }
                }
                button("Run now", color: Theme.brass) {
                    Task { await store.runJanitorNow() }
                }
                if store.janitorBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
            }
            .disabled(store.janitorBusy)

            Text("Similarity: \(store.similarityEngine.label)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.inkDim.opacity(0.8))

            if let summary = store.janitorSummary {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkDim)
            }

            // A preview is a claim about what would happen, so it has to be
            // specific enough to disagree with — hence each proposal's own
            // rationale rather than a count.
            ForEach(store.janitorPreview, id: \.fingerprint) { proposal in
                HStack(alignment: .top, spacing: 6) {
                    Text(proposal.risk == .cosmetic ? "AUTO" : "QUEUE")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(proposal.risk == .cosmetic ? Theme.accent : Theme.brass)
                        .frame(width: 38, alignment: .leading)
                    Text(proposal.rationale)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkDim)
                }
            }
        }
    }

    private func button(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border, lineWidth: 1))
    }
}

/// One flag, on the note whose detail view is already open. The main global
/// queue uses `ReviewClusterCard` instead — see there for why duplicates get
/// grouped and this doesn't.
private struct ReviewQueueRow: View {
    @EnvironmentObject var store: AppStore
    let note: Note
    let flag: ReviewFlag

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(flag.reason.withoutJanitorMarker)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.ink)
                // Without this, SwiftUI is free to collapse a Text nested this
                // deep in flexible VStacks down to one line with a trailing
                // ellipsis instead of actually wrapping — the bug that made the
                // review queue unreadable. This pins the height to the wrapped
                // content instead of letting the layout guess.
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                actionButton("Accept", color: Theme.accent) {
                    store.resolve(note: note, flag: flag, outcome: "accepted")
                }
                actionButton("Reject", color: Theme.crit) {
                    store.resolve(note: note, flag: flag, outcome: "rejected")
                }
            }
        }
        .padding(9)
        .background(Theme.background)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border, lineWidth: 1))
    }
}

/// One card per `ReviewCluster` — one decision, however many flags it took to
/// raise it. For a duplicate group, Accept/Reject resolves every flag in the
/// group at once (`AppStore.resolve(cluster:outcome:)`), which is exactly what
/// pressing each one individually would have done, minus the repetition.
/// The card's layout assumes the wide main column, not the old 260pt sidebar —
/// note titles are long file paths, and side-by-side title-plus-button
/// squeezed to a narrow width was truncating the *button label itself*
/// ("Keep this o…"). Full width fixes that by construction rather than by
/// tuning font sizes.
private struct ReviewClusterCard: View {
    @EnvironmentObject var store: AppStore
    let cluster: ReviewCluster

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if cluster.isDuplicateGroup {
                Text("\(cluster.notes.count) NOTES THAT LOOK LIKE THE SAME THING")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.brass)
            } else if let note = cluster.notes.first {
                Button(action: { store.selectNote(note.id) }) {
                    Text(note.title)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .underline()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            }

            Text(cluster.summary)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            if cluster.isDuplicateGroup {
                // Advisory only — see AssistantView. A mistyped link or an
                // orphan doesn't need judgement about which of two bodies is
                // "the real one," so there's nothing useful to ask about those.
                if let recommendation = store.clusterRecommendations[cluster.id] {
                    Text(recommendation == "…" ? "asking the assistant…" : recommendation)
                        .font(.system(size: 12, design: recommendation == "…" ? .monospaced : .default))
                        .foregroundStyle(Theme.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .background(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                } else {
                    Button("Not sure which to keep? Ask the assistant") {
                        Task { await store.draftRecommendation(for: cluster) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                }

                // One row per note: a preview of what it actually says, plus
                // its own "Keep this one." This is the honest version of what
                // used to be a generic Accept/Reject that changed nothing —
                // now the button says exactly what pressing it does, and
                // there's room to read enough to decide without opening it.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cluster.notes) { note in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .top, spacing: 10) {
                                Button(action: { store.selectNote(note.id) }) {
                                    Text(note.title)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(Theme.ink)
                                        .underline()
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .buttonStyle(.plain)
                                .layoutPriority(1)

                                Spacer(minLength: 12)

                                actionButton("Keep this one", color: Theme.accent) {
                                    store.consolidate(cluster: cluster, keeping: note)
                                }
                                .fixedSize()
                            }
                            if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(preview(of: note.body))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkDim)
                                    .lineLimit(2)
                            }
                        }
                        .padding(8)
                        .background(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                }

                actionButton("These aren't the same — leave them alone", color: Theme.inkDim) {
                    store.resolve(cluster: cluster, outcome: "not a duplicate")
                }
            } else {
                HStack(spacing: 8) {
                    actionButton("Got it, I'll take care of it", color: Theme.accent) {
                        store.resolve(cluster: cluster, outcome: "acknowledged")
                    }
                    actionButton("Not important, dismiss", color: Theme.inkDim) {
                        store.resolve(cluster: cluster, outcome: "dismissed")
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.background)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }

    private func preview(of body: String) -> String {
        let collapsed = body
            .split(separator: "\n")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.count > 160 ? String(collapsed.prefix(160)) + "…" : collapsed
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border, lineWidth: 1))
    }
}
