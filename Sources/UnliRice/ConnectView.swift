import SwiftUI
import UnliRiceCore

/// One screen, one job: point an AI tool at these notes.
struct ConnectView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.availableTargets.enumerated()), id: \.element.id) { index, target in
                        if index > 0 {
                            Divider().opacity(0.1)
                        }
                        ConnectorRow(target: target)
                    }
                }
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.01)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Connect")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("Add a tool…") { store.addCustomTarget() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
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
        VStack(alignment: .leading, spacing: 16) {
            HouseRulesEditor()

            Card(
                title: "Storage Location",
                subtitle: "Where your permanent event log and notes are physically saved on disk.",
                icon: "cylinder.split.1x2.fill"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("All \(store.notes.count + store.archivedNotes.count) notes are stored at:")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkDim)
                        if !store.usingDefaultDataFolder {
                            Text("custom folder")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .foregroundStyle(Theme.brass)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.brass.opacity(0.6), lineWidth: 1))
                        }
                    }
                    
                    Text(store.dataURL.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(8)
                        .background(Color.black.opacity(0.25))
                        .cornerRadius(4)
                    
                    HStack(spacing: 12) {
                        if !store.usingDefaultDataFolder {
                            Button("Use Default Location") { store.useDefaultDataFolder() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                        
                        Button("Switch Store…") { store.chooseExistingVault() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.brass)
                    }
                    .padding(.top, 4)
                }
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

/// The instructions a connected assistant reads at the start of a session.
private struct HouseRulesEditor: View {
    @EnvironmentObject var store: AppStore
    @State private var expanded = false
    @State private var showingTemplates = false

    var body: some View {
        Card(
            title: "House Rules",
            subtitle: "Conventions your connected assistant reads at the start of a session.",
            icon: "scroll.fill"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(store.houseRulesNote == nil ? Theme.inkDim : Theme.emerald)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Button("Choose Template…") { showingTemplates = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(Theme.brass)
                        .background(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))

                    Button(expanded ? "Hide" : "Edit") { expanded.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(Theme.ink)
                        .background(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))

                    Button(saveButtonTitle) {
                        store.saveHouseRules()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .foregroundStyle(saveDisabled ? Theme.inkDim : Theme.onAccent)
                    .background(saveDisabled ? Color.clear : Theme.accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(saveDisabled ? Theme.border : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(saveDisabled)
                }

                if expanded {
                    TextEditor(text: $store.houseRulesText)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.25))
                        .frame(height: 220)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))

                    HStack {
                        Text("Written to a note your assistant reads. Edit freely — these are your conventions.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkDim.opacity(0.85))
                        Spacer()
                        Button("Reset to default") { store.resetHouseRules() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkDim)
                    }
                }

                if let error = store.houseRulesStateError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.crit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $showingTemplates) {
            HouseRulesPresetGalleryView {
                expanded = true
            }
            .environmentObject(store)
        }
    }

    private var saveDisabled: Bool {
        store.houseRulesAreSaved && store.houseRulesNote?.archived != true
    }

    private var saveButtonTitle: String {
        guard let note = store.houseRulesNote else { return "Save to notes" }
        return note.archived ? "Restore and update" : "Update note"
    }

    private var statusLine: String {
        guard let note = store.houseRulesNote else {
            return "Not saved yet — your assistant won't know these conventions."
        }
        if note.archived {
            return "“\(note.title)” is archived — restore it so assistants can find it."
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

    @State private var presence: MCPConfigWriter.Presence = .noFile
    @State private var showingSnippet = false

    private var result: ConnectionResult? { store.result(forTargetID: target.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(String(target.displayName.prefix(1)))
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Theme.brass)
                    .background(Theme.brass.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .font(.system(size: 13, weight: .semibold))
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
                Text("Your previous config was backed up to \(backup.lastPathComponent)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkDim)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .onAppear { refresh() }
        .onChange(of: store.connectionResults) { _ in refresh() }
        .onChange(of: store.targetProjectFolders) { _ in refresh() }
    }

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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.emerald)
                Button("Reconnect") { store.connect(target) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            }
        case .stale:
            HStack(spacing: 8) {
                Text("Out of date")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.brass)
                actionButton("Update")
            }
        case .unreadable:
            Text("Can't read file")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.crit)
        case .noFile, .absent:
            if target.supportsAutomaticWrite {
                actionButton(target.requiresProjectFolder
                    && store.targetProjectFolders[target.id] == nil ? "Choose folder…" : "Connect")
            } else {
                Button(showingSnippet ? "Hide Config" : "Copy Config") {
                    if showingSnippet {
                        showingSnippet = false
                    } else {
                        showingSnippet = true
                        store.copySnippet(store.snippet(for: target))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
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
        .font(.system(size: 11.5, weight: .bold))
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

private struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkDim.opacity(0.8))
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.01)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
