import SecondBrainCore
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

            sidebarRow("All Notes", active: true)
            sidebarRow("Review Queue", badge: store.pending.count)
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

    private func sidebarRow(_ title: String, active: Bool = false, badge: Int? = nil) -> some View {
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
        .padding(.horizontal, 10)
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("All Notes")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(store.notes.count) notes total · append-only")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }

            PromptRow()

            if let error = store.errorMessage {
                Text("Couldn't read the event log: \(error)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.crit)
            } else if store.visibleNotes.isEmpty {
                Text(store.visibleCount == 0 ? " " : "No notes yet — add one below to get started.")
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
            NewNoteRow()
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
            chip("What's waiting on me?") { store.showWaiting() }
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

private struct NoteList: View {
    let notes: [Note]

    var body: some View {
        VStack(spacing: 1) {
            ForEach(notes) { note in
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
                    Text(note.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.panel)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
    }
}

private struct NewNoteRow: View {
    @EnvironmentObject var store: AppStore
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                TextField("New note title…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .padding(7)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.plain)
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

    private func add() {
        store.createNote(title: title)
        title = ""
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

                Text("No MLX janitor is running yet — this preference is saved, but nothing reads it until that piece exists.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkDim.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    header("Review queue")
                    Spacer()
                    if !store.pending.isEmpty {
                        Text("\(store.pending.count) pending")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.brass)
                    }
                }
                if store.pending.isEmpty {
                    Text("Nothing flagged right now.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim)
                } else {
                    ForEach(store.pending, id: \.flag.id) { item in
                        ReviewQueueRow(note: item.note, flag: item.flag)
                    }
                }
            }

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

private struct ReviewQueueRow: View {
    @EnvironmentObject var store: AppStore
    let note: Note
    let flag: ReviewFlag

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(note.title): \(flag.reason)")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.ink)
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
