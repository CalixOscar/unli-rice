import SwiftUI
import UnliRiceCore

/// One screen, one job: point an AI tool at these notes.
///
/// This replaces a three-stage wizard (`SetupStage.start` → `.chooseTargets` →
/// `.results`) that turned five independent switches into a linear flow. The
/// problems it had were all the same problem: state. Ticking Cursor and ticking
/// Claude Desktop had to be committed together; the results screen was a
/// *different page* from the list, so "is Cursor connected?" was unanswerable
/// once you'd navigated away; and a returning user who wanted to add one more
/// tool was walked back through an autopilot decision they'd already made.
///
/// A table has no stages. Every row reads its own current state from disk on
/// appear (`MCPConfigWriter.presence`, which writes nothing), acts alone, and
/// reports its outcome in place. Coming back later shows the truth rather than
/// whatever the last session happened to leave in memory.
struct ConnectView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.availableTargets.enumerated()), id: \.element.id) { index, target in
                        if index > 0 {
                            Divider().opacity(0.25)
                        }
                        ConnectorRow(target: target)
                    }
                }
                .background(Theme.panel.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Connect")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Add a tool…") { store.addCustomTarget() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            }

            Text("Unli Rice is memory your AI tools share. Connect one and it can read what you've saved, and write back what's worth keeping next time.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HouseRulesEditor()

            Divider().opacity(0.2)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes are stored at")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkDim)
                    Text(store.dataURL.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Button("Use another folder…") { store.chooseExistingVault() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.crit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The instructions a connected assistant reads at the start of a session —
/// shown as the text it is, and editable.
///
/// This replaced an "Autopilot" switch whose only effect was writing this text
/// into a note. A switch is the wrong control for a prompt: it offers a choice
/// between someone else's wording and nothing at all, when what a person wants
/// is to change a line — add their own conventions, drop a rule that doesn't
/// apply to how they work. The switch was also inert in both directions by the
/// time you'd have used it, since nothing persisted its state and the note it
/// guarded was written once and never again.
///
/// So: the text, a Save button, and a Reset. Saving is explicit rather than a
/// side effect of connecting a tool, because a note appearing in your store is
/// a thing you should have asked for.
private struct HouseRulesEditor: View {
    @EnvironmentObject var store: AppStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("House rules")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(store.houseRulesNote == nil ? Theme.inkDim : Theme.emerald)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(expanded ? "Hide" : "Edit") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))

                Button(store.houseRulesNote == nil ? "Save to notes" : "Update the note") {
                    store.saveHouseRules()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(store.houseRulesAreSaved ? Theme.inkDim : Theme.onAccent)
                .background(store.houseRulesAreSaved ? Color.clear : Theme.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(store.houseRulesAreSaved ? Theme.border : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // Nothing to save is a real state, and on an append-only log
                // pressing it anyway would file a second copy of the same text.
                .disabled(store.houseRulesAreSaved)
            }

            if expanded {
                TextEditor(text: $store.houseRulesText)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.25))
                    .frame(height: 220)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))

                HStack {
                    Text("Written to a note your assistant reads. Edit freely — these are your conventions, not ours.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkDim.opacity(0.85))
                    Spacer()
                    Button("Reset to default") { store.resetHouseRules() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkDim)
                }
            }
        }
    }

    private var statusLine: String {
        guard let note = store.houseRulesNote else {
            return "Not saved yet — your assistant won't know these conventions until it is."
        }
        return store.houseRulesAreSaved
            ? "Saved as “\(note.title)”."
            : "Edited since it was saved to “\(note.title)”."
    }
}

/// A single tool. Reads its own state, acts alone, reports in place.
private struct ConnectorRow: View {
    @EnvironmentObject var store: AppStore
    let target: MCPTarget

    /// Cached rather than recomputed in `body`: `presence` hits the filesystem,
    /// and `body` runs on every unrelated `@Published` change in the store.
    @State private var presence: MCPConfigWriter.Presence = .noFile
    @State private var showingSnippet = false

    private var result: ConnectionResult? { store.result(forTargetID: target.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(String(target.displayName.prefix(1)))
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Theme.brass)
                    .background(Theme.brass.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(folderQualifiedDetail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)
                statusView
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if showingSnippet {
                snippetBlock
            }

            if let result, case .written(let backup) = result.status, let backup {
                // This app edited a file it didn't create. The user is entitled
                // to know exactly how to undo that, without going looking.
                Text("Your previous config was backed up to \(backup.lastPathComponent)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkDim)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .onAppear { refresh() }
        // Reconnecting, or picking a project folder, changes what's on disk.
        .onChange(of: store.connectionResults) { _ in refresh() }
        .onChange(of: store.targetProjectFolders) { _ in refresh() }
    }

    /// For project-scoped tools, the chosen folder is the useful half of the
    /// path — ".mcp.json in a project folder you choose" stops being true the
    /// moment they've chosen one.
    private var folderQualifiedDetail: String {
        guard target.requiresProjectFolder, let folder = store.targetProjectFolders[target.id] else {
            return target.detail
        }
        return folder.path
    }

    @ViewBuilder
    private var statusView: some View {
        switch presence {
        case .current:
            HStack(spacing: 8) {
                Label("Connected", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.emerald)
                Button("Reconnect") { store.connect(target) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkDim)
            }
        case .stale:
            // Not "Connected" and not "Connect": it points somewhere, just not
            // here. Saying either would be a lie in one direction or the other.
            HStack(spacing: 8) {
                Text("Out of date")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.brass)
                actionButton("Update")
            }
        case .unreadable:
            Text("Can't read that file")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.crit)
        case .noFile, .absent:
            if target.supportsAutomaticWrite {
                actionButton(target.requiresProjectFolder
                    && store.targetProjectFolders[target.id] == nil ? "Choose folder…" : "Connect")
            } else {
                // Codex TOML. We don't write these — see MCPConfigFormat.
                Button(showingSnippet ? "Hide config" : "Copy config") {
                    if showingSnippet {
                        showingSnippet = false
                    } else {
                        showingSnippet = true
                        store.copySnippet(store.snippet(for: target))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(Theme.ink)
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    private func actionButton(_ label: String) -> some View {
        Button(label) {
            store.connect(target)
            refresh()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .foregroundStyle(Theme.onAccent)
        .background(Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var snippetBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste this into \(target.detail.components(separatedBy: " — ").first ?? target.detail)")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.brass)
            ScrollView {
                Text(store.snippet(for: target))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 160)
            .background(Color.black.opacity(0.25))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func refresh() {
        presence = store.presence(of: target)
    }
}
