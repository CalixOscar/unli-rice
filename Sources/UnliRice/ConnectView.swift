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
                .liquidGlass(cornerRadius: 8)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Connect")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Add a tool…") { store.addCustomTarget() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.onSolidFill)
                    .solidControl(cornerRadius: 6)
            }

            Text("Unli Rice is memory your AI tools share. Copy a configuration block, paste it into your tool yourself, and restart that tool to connect.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
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
                            .foregroundStyle(Theme.textSecondary)
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
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(8)
                        .background(Theme.bgField)
                        .cornerRadius(4)
                    
                    HStack(spacing: 12) {
                        if !store.usingDefaultDataFolder {
                            Button("Use Default Location") { store.useDefaultDataFolder() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.accentColor)
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
                        .foregroundStyle(store.houseRulesNote == nil ? Theme.textSecondary : Theme.emerald)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Button("Choose Template…") { showingTemplates = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(Theme.brass)
                        .solidControl(cornerRadius: 6)

                    Button(expanded ? "Hide" : "Edit") { expanded.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .foregroundStyle(Theme.onSolidFill)
                        .solidControl(cornerRadius: 6)

                    Button(saveButtonTitle) {
                        store.saveHouseRules()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .foregroundStyle(saveDisabled ? Theme.textSecondary : Theme.onAccent)
                    .background(saveDisabled ? Color.clear : Theme.accentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(saveDisabled ? Theme.borderLight : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(saveDisabled)
                }

                if expanded {
                    TextEditor(text: $store.houseRulesText)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Theme.bgField)
                        .frame(height: 220)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))

                    HStack {
                        Text("Written to a note your assistant reads. Edit freely — these are your conventions.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary.opacity(0.85))
                        Spacer()
                        Button("Reset to default") { store.resetHouseRules() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textSecondary)
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

    @State private var showingSnippet = false

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
                        .foregroundStyle(Theme.textPrimary)
                    Text(target.detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)
                Button(showingSnippet ? "Copy Again" : "Copy Configuration") {
                    store.copyConfiguration(for: target)
                    showingSnippet = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(Theme.onSolidFill)
                .solidControl(cornerRadius: 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if showingSnippet {
                snippetBlock
            }

            Text("Unli Rice never opens or edits this file. Merge the copied block manually, keeping any servers already there.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }

    private var snippetBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Paste into \(target.detail)")
                Spacer()
                Button("Hide") { showingSnippet = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
            }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.brass)
            ScrollView {
                Text(store.snippet(for: target))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 160)
            .background(Theme.bgField)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
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
                    .foregroundStyle(Theme.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 8)
    }
}
