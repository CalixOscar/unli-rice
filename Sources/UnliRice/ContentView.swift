import UnliRiceCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            // Dark space background
            Theme.background
                .ignoresSafeArea()

            // Glowing neon background blobs
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Theme.violet.opacity(0.18))
                        .frame(width: 450, height: 450)
                        .blur(radius: 90)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    Circle()
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 350, height: 350)
                        .blur(radius: 80)
                        .position(x: geo.size.width * 0.15, y: geo.size.height * 0.8)

                    Circle()
                        .fill(Theme.brass.opacity(0.12))
                        .frame(width: 380, height: 380)
                        .blur(radius: 95)
                        .position(x: geo.size.width * 0.85, y: geo.size.height * 0.2)
                }
                .ignoresSafeArea()
            }

            // Main structure
            // Two columns, not three. The third was `AutonomyPanel`, 260pt of
            // settings and manual triggers pinned to every screen — see
            // `AutomationView`, which is where all of it went.
            HStack(spacing: 0) {
                sidebar
                Divider().opacity(0.3)
                mainColumn
            }
        }
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

            sidebarRow(
                "Home",
                active: store.showingHome || (store.selectedNoteID == nil && !store.showingArchived
                    && !store.showingGraph && !store.showingGetStarted && !store.showingNeedsYou && !store.showingSetup
                    && !store.showingReviewQueue && !store.showingRetrospective
                    && !store.showingNotices && !store.showingAutomation && !store.showingProfileBuilder
                    && !store.showingProfileManager && !store.showingTrustCenter && store.notes.isEmpty)
            ) {
                store.selectNote(nil)
                store.showHome()
            }

            sidebarRow(
                "Needs you",
                active: store.selectedNoteID == nil && (store.showingNeedsYou || store.showingReviewQueue),
                badge: store.pending.count + store.unreadNoticeCount
            ) {
                store.selectNote(nil)
                store.showNeedsYou()
            }

            sidebarRow(
                "Notes",
                active: store.selectedNoteID == nil && !store.showingHome && !store.showingNeedsYou
                    && !store.showingSetup && !store.showingGetStarted && !store.showingRetrospective
                    && !store.showingAutomation && !store.showingTrustCenter && !store.showingNotices
                    && !store.showingProfileBuilder && !store.showingProfileManager
            ) {
                store.selectNote(nil)
                store.showAllNotes()
            }

            sidebarRow(
                "Setup",
                active: store.selectedNoteID == nil && (store.showingSetup || store.showingGetStarted || store.showingProfileBuilder || store.showingProfileManager)
            ) {
                store.selectNote(nil)
                store.showSetup()
            }

            sidebarRow(
                "Looking back",
                active: store.selectedNoteID == nil && store.showingRetrospective
            ) {
                store.selectNote(nil)
                store.showRetrospective()
            }

            if store.advancedModeEnabled {
                Divider().opacity(0.15).padding(.horizontal, 14).padding(.vertical, 6)

                sidebarRow(
                    "Trust Center",
                    active: store.selectedNoteID == nil && store.showingTrustCenter
                ) {
                    store.selectNote(nil)
                    store.showTrustCenter()
                }
                sidebarRow(
                    "Notifications",
                    active: store.selectedNoteID == nil && store.showingNotices,
                    badge: store.unreadNoticeCount
                ) {
                    store.selectNote(nil)
                    store.showNotices()
                }
                sidebarRow(
                    "Archived",
                    active: store.selectedNoteID == nil && store.showingArchived,
                    badge: store.archivedNotes.count
                ) {
                    store.selectNote(nil)
                    store.showArchived()
                }
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
        .background(Color.black.opacity(0.18))
        .background(.ultraThinMaterial)
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
            if store.showingProfileBuilder {
                ProfileBuilderView()
            } else if store.showingProfileManager {
                ProfileManagerView()
            } else if store.showingNeedsYou {
                NeedsYouView()
            } else if store.showingSetup || store.showingGetStarted {
                SetupView()
            } else if store.showingHome {
                HomeView()
            } else if let note = store.selectedNote {
                NoteDetailView(note: note)
            } else if store.showingReviewQueue {
                NeedsYouView()
            } else if store.showingNotices {
                NoticeCenterView()
            } else if store.showingRetrospective {
                RetrospectiveView()
            } else if store.showingGraph {
                NoteGraphView()
            } else if store.showingAutomation {
                AutomationView()
            } else if store.showingTrustCenter {
                TrustCenterView()
            } else {
                noteListColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Header and composer are pinned; only the list scrolls.
    ///
    /// It didn't scroll at all before — `NoteList` was a plain `VStack` inside
    /// this `VStack`, so on a corpus of 190 notes every row past the window's
    /// height was rendered off-screen and unreachable, and `NewNoteRow` was
    /// pushed out of the window with them. Wrapping the whole column in a
    /// `ScrollView` would have fixed the reachability and taken the composer
    /// with it; keeping the chrome outside the scroller is what makes a long
    /// list usable rather than merely present.
    private var noteListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            noteListHeader
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if let error = store.errorMessage {
                Text("Couldn't read the event log: \(error)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.crit)
                    .padding(20)
            } else if store.visibleNotes.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkDim)
                    .padding(20)
                Spacer()
            } else {
                ScrollView {
                    // Lazy, not eager: ingest can add 40 notes in one click, and
                    // the eager VStack built a row view for every note in the
                    // corpus on every redraw.
                    LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                        ForEach(store.visibleSections) { section in
                            Section {
                                ForEach(section.notes) { note in
                                    NoteRow(note: note)
                                }
                            } header: {
                                sectionHeader(section.title)
                            }
                        }

                        if store.hiddenNoteCount > 0 {
                            Button("Show \(store.hiddenNoteCount) more") { store.showEverything() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.statusMessage)
                    .font(.system(size: 11.5))
                    .italic()
                    .foregroundStyle(Theme.inkDim)
                if !store.showingArchived {
                    NewNoteRow()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyMessage: String {
        if !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Nothing matches “\(store.searchText)”."
        }
        return store.showingArchived
            ? "Nothing archived."
            : "No notes yet — add one below to get started."
    }

    @ViewBuilder
    private var noteListHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.showingArchived ? "Archived" : "All Notes")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                let total = store.showingArchived ? store.archivedNotes.count : store.notes.count
                Text("\(store.visibleNotes.count) of \(total) · append-only")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }

            SearchField()

            if store.showingArchived {
                ArchiveToolbar()
            } else {
                PromptRow()
            }
        }
        .padding(.bottom, 12)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.top, 6)
        .background(Theme.background.opacity(0.92))
    }
}

/// Filters the list as you type. Plain, immediate, no submit — with 190 notes
/// the fastest route to one of them is typing three letters of it, and a
/// search that needs a return key first isn't that.
private struct SearchField: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)
            TextField("Search titles, bodies, tags…", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !store.searchText.isEmpty {
                Button(action: { store.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
    }
}

/// The Archived pane's own controls: the two things you can only do to
/// something already set aside.
private struct ArchiveToolbar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            Text(store.archiveSelection.isEmpty
                 ? "Archiving never deleted anything. Tick notes to trash them for good."
                 : "\(store.archiveSelection.count) selected")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkDim)

            Spacer()

            CleanupMenu(prompts: CleanupPrompts.archive, label: "Ask an LLM…")

            Button("Reveal Trash") { store.revealTrashFolder() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(Theme.ink)
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))

            // Destructive, so it is styled as such and stays disabled until
            // something is actually ticked — the only irreversible control in
            // the app should never be reachable by a stray click.
            Button("Move to Trash") { store.moveSelectedToTrash() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(store.archiveSelection.isEmpty ? Theme.inkDim : Theme.crit)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(store.archiveSelection.isEmpty ? Theme.border : Theme.crit, lineWidth: 1)
                )
                .disabled(store.archiveSelection.isEmpty)
        }
    }
}

/// The clipboard-prompt menu, shared by Review Notes and Archived.
///
/// Every item copies a sentence and nothing else. That's the design: the work
/// these describe — judging which of four near-identical notes is the real one
/// — needs a model that can read all of them, and the model that can do that is
/// the one the user already has connected. See `CleanupPrompts`.
struct CleanupMenu: View {
    @EnvironmentObject var store: AppStore
    let prompts: [CleanupPrompt]
    var label: String = "Clean up…"

    var body: some View {
        Menu {
            ForEach(prompts) { prompt in
                Button {
                    store.copyPrompt(prompt)
                } label: {
                    Text(prompt.title)
                    Text(prompt.blurb)
                }
            }
            Divider()
            Text("Each copies a prompt to paste into your assistant.")
                .foregroundColor(Theme.ink)
        } label: {
            Text(label)
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Copies the review prompt for whichever configured tool the user intends to
/// use. The app deliberately does not inspect another tool's config to claim a
/// live connection state.
struct AIReviewMenu: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Menu {
            ForEach(store.availableTargets) { target in
                Button {
                    store.copyReviewPrompt(for: target)
                } label: {
                    Text(target.displayName)
                }
            }
            Divider()
            Text("Copies a prompt listing all pending reviews to paste into the LLM.")
                .foregroundColor(Theme.ink)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                Text("Resolve with AI…")
            }
            .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.pending.isEmpty)
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
            HStack(spacing: 10) {
                Text("Review Notes")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(store.pending.count) item\(store.pending.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)

                AIReviewMenu()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))

                // Sits here rather than in the empty state because "nothing is
                // flagged" is exactly when bulk tidying is worth offering: the
                // janitor found nothing *it* can judge, which says nothing about
                // whether 144 ingested session logs are worth keeping.
                CleanupMenu(prompts: CleanupPrompts.review)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            }

            // Answers "why am I seeing this at all" before the cards do — a
            // person shouldn't have to infer that from the presence of
            // action buttons.
            // Two stale claims fixed at once: the janitor's controls are no
            // longer "in the panel on the right" (there is no right panel), and
            // an empty queue said nothing about how it ever gets filled. The
            // buttons are now on this page, because "run the thing that puts
            // items here" belongs on the page that lists them.
            Text("The janitor reads your notes and flags what it can't decide alone — likely duplicates, notes worth merging. It never changes anything itself; everything below waits for your OK. Nothing here is deleted by any button. The closest is Archive, which is always reversible.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Preview") { Task { await store.previewJanitor() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.accent)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))

                Button("Run the janitor") { Task { await store.runJanitorNow() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.brass)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))

                if store.janitorBusy {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }

                if let summary = store.janitorSummary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkDim)
                }
            }
            .disabled(store.janitorBusy)

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
            chip("Everything") { store.showEverything() }
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

/// One row per note. Tapping the row opens `NoteDetailView` — the list itself
/// stays a title-first index.
///
/// The row carries two things it didn't before. **Archive**, because archiving
/// used to require opening the note first, which is backwards: you decide a
/// note is noise by glancing at its title, not by reading it. And in the
/// Archived pane, a **tick box**, because the only destructive action in the
/// app operates on a set and needs a way to express one.
private struct NoteRow: View {
    @EnvironmentObject var store: AppStore
    let note: Note

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if store.showingArchived {
                Button(action: { store.toggleArchiveSelection(note) }) {
                    Image(systemName: store.archiveSelection.contains(note.id)
                          ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundStyle(store.archiveSelection.contains(note.id) ? Theme.accent : Theme.inkDim)
                }
                .buttonStyle(.plain)
            }

            Button(action: { store.selectNote(note.id) }) {
                HStack(spacing: 8) {
                    // Only shown when it isn't the overwhelming default. With
                    // every note in the corpus stamped "claude", the badge was
                    // pure noise repeated 190 times; it earns its place only
                    // where it distinguishes something.
                    if let source = note.sources.sorted().first, source != "claude" {
                        Text(source)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .foregroundStyle(Theme.brass)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.brass.opacity(0.6), lineWidth: 1))
                    }

                    Text(note.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    // The first line of the body, dimmed. This is what makes
                    // 144 rows that all begin "Session:" tellable apart at a
                    // glance rather than only after opening each one.
                    if let preview = bodyPreview {
                        Text(preview)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.inkDim.opacity(0.75))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if note.flags.contains(where: { !$0.resolved }) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.brass)
                    }
                    Text(note.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Reserves its slot whether or not it's visible, so titles don't
            // reflow under the pointer as it moves down the list.
            Group {
                if hovering {
                    Button(action: { rowAction() }) {
                        Image(systemName: store.showingArchived ? "tray.and.arrow.up" : "archivebox")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkDim)
                    }
                    .buttonStyle(.plain)
                    .help(store.showingArchived ? "Restore to All Notes" : "Archive (reversible)")
                } else {
                    Color.clear
                }
            }
            .frame(width: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovering ? Theme.panel.opacity(0.9) : Theme.panel.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering = $0 }
    }

    /// The first line worth reading, which is rarely the first line.
    ///
    /// Ingested sessions all open with the same four `**Project:** …`
    /// `**When:** …` metadata lines, so taking line one gave all 144 of them an
    /// identical preview — reproducing the exact problem the preview exists to
    /// solve. Metadata lines are skipped in favour of prose; the quoted line
    /// after `**Opened with:**` is the user's own first message, which is the
    /// single most identifying thing in the note.
    private var bodyPreview: String? {
        let lines = note.body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let isMetadata: (String) -> Bool = { $0.hasPrefix("**") && $0.contains(":**") }
        let chosen = lines.first { $0.hasPrefix("> ") }
            ?? lines.first { !isMetadata($0) }
            ?? lines.first

        guard let chosen else { return nil }
        let cleaned = chosen
            .replacingOccurrences(of: "> ", with: "")
            .replacingOccurrences(of: "**", with: "")
        return "— " + cleaned.prefix(110)
    }

    private func rowAction() {
        if store.showingArchived {
            store.unarchive(note)
        } else {
            store.archiveFromList(note)
        }
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
                    .foregroundStyle(Theme.onAccent)
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
        .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
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
    @State private var history: [Event] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                backRow
                header
                provenanceSection
                bodyText
                tagsSection
                linksSection
                flagsSection
                historySection
                appendSection
            }
            .padding(20)
        }
        .onAppear { history = store.noteHistory(note) }
        .onChange(of: note.updatedAt) { _ in history = store.noteHistory(note) }
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

    @ViewBuilder
    private var provenanceSection: some View {
        let provenance = store.provenance(note)
        if provenance.rawFilename != nil || provenance.sourceFilePath != nil
            || provenance.projectPath != nil || provenance.sessionID != nil {
            VStack(alignment: .leading, spacing: 7) {
                sectionHeader("Provenance")
                if let path = provenance.sourceFilePath {
                    provenanceRow("Original file", value: path)
                }
                if let project = provenance.projectPath {
                    provenanceRow("Project", value: project)
                }
                if let session = provenance.sessionID {
                    provenanceRow("Session", value: session)
                }
                if let raw = provenance.rawFilename {
                    provenanceRow("Preserved raw copy", value: raw)
                }
                HStack(spacing: 8) {
                    if provenance.sourceFilePath != nil {
                        provenanceButton("Reveal original") { store.revealOriginalSource(for: note) }
                    }
                    if provenance.rawFilename != nil {
                        provenanceButton("Reveal raw copy") { store.revealRawSource(for: note) }
                    }
                }
            }
            .padding(12)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func provenanceRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func provenanceButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(Theme.accent)
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
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .disabled(draftAppend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("History")
                Spacer()
                Text("\(history.count) immutable event\(history.count == 1 ? "" : "s")")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }
            ForEach(Array(history.reversed())) { event in
                EventHistoryRow(event: event)
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

private struct EventHistoryRow: View {
    let event: Event

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 15, height: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("by \(event.source)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.brass)
                    Spacer()
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(9)
        .background(Theme.panel.opacity(0.65))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border.opacity(0.7), lineWidth: 1))
    }

    private var label: String {
        switch event.kind {
        case .created: return "Created"
        case .appended: return "Appended"
        case .tagged: return "Added tag"
        case .untagged: return "Removed tag"
        case .archived: return "Archived"
        case .unarchived: return "Restored from archive"
        case .flagged: return "Flagged for review"
        case .reviewResolved: return "Review resolved"
        }
    }

    private var detail: String? {
        switch event.kind {
        case .created, .appended:
            return event.text
        case .tagged, .untagged:
            return event.tag.map { "#\($0)" }
        case .archived, .flagged, .reviewResolved:
            return event.reason
        case .unarchived:
            return nil
        }
    }

    private var symbol: String {
        switch event.kind {
        case .created: return "plus.circle.fill"
        case .appended: return "text.badge.plus"
        case .tagged: return "tag.fill"
        case .untagged: return "tag.slash"
        case .archived: return "archivebox.fill"
        case .unarchived: return "tray.and.arrow.up.fill"
        case .flagged: return "flag.fill"
        case .reviewResolved: return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch event.kind {
        case .archived, .untagged: return Theme.crit
        case .flagged: return Theme.brass
        case .unarchived, .reviewResolved: return Theme.emerald
        default: return Theme.accent
        }
    }
}

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
struct ReviewClusterCard: View {
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
                // There used to be an "ask the assistant which to keep" button
                // here, backed by the bundled local model. Both are gone: the
                // model was removed once measured (PROJECT_NOTES.md), and a
                // 1.7B model's opinion on which of two notes is "the real one"
                // was never worth the weight it carried in a UI that otherwise
                // hands every judgement to the human. An agent connected over
                // MCP can be asked the same question, with a better answer.

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
