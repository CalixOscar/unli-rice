import SwiftUI
import UnliRiceCore

struct HouseRulesPresetGalleryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPresetID: String? = HouseRulesPreset.builtIn.first?.id
    @State private var renamingPresetID: String?
    @State private var renameText = ""
    @State private var pendingDelete: HouseRulesPreset?

    let onUseDraft: () -> Void

    private var selectedPreset: HouseRulesPreset? {
        allPresets.first { $0.id == selectedPresetID }
    }

    private var allPresets: [HouseRulesPreset] {
        HouseRulesPreset.builtIn + store.customHouseRulesPresets
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("House Rules Templates")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Choose a starting point. Nothing is written to your notes until you save the draft.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkDim)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkDim)
            }
            .padding(18)

            Divider().overlay(Theme.border)

            HSplitView {
                presetList
                    .frame(minWidth: 235, idealWidth: 260, maxWidth: 310)
                preview
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Theme.background)
        .confirmationDialog(
            "Delete this custom template?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete Template", role: .destructive) {
                guard let preset = pendingDelete else { return }
                store.removeCustomHouseRulesPreset(preset)
                if selectedPresetID == preset.id {
                    selectedPresetID = HouseRulesPreset.builtIn.first?.id
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This only removes the reusable template from this vault. It does not change note history.")
        }
    }

    private var presetList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedPresetID) {
                Section("Built-In") {
                    ForEach(HouseRulesPreset.builtIn) { preset in
                        presetRow(preset)
                            .tag(Optional(preset.id))
                    }
                }

                Section("Custom") {
                    if store.customHouseRulesPresets.isEmpty {
                        Text("No imported templates")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkDim)
                    } else {
                        ForEach(store.customHouseRulesPresets) { preset in
                            presetRow(preset)
                                .tag(Optional(preset.id))
                                .contextMenu {
                                    Button("Rename…") { beginRename(preset) }
                                    Button("Duplicate") {
                                        let copy = store.duplicateCustomHouseRulesPreset(preset)
                                        selectedPresetID = copy.id
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) { pendingDelete = preset }
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            Divider().overlay(Theme.border)

            Button {
                if let imported = store.importHouseRulesPreset() {
                    selectedPresetID = imported.id
                }
            } label: {
                Label("Import .md or .txt…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.brass)
            .padding(14)
        }
        .background(Theme.panel)
    }

    private func presetRow(_ preset: HouseRulesPreset) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(preset.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(preset.summary)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkDim)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var preview: some View {
        if let preset = selectedPreset {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(preset.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkDim)
                    }
                    Spacer()
                    Text("~\(preset.approximateTokenCount) tokens · \(preset.characterCount) characters")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.inkDim)
                }

                if renamingPresetID == preset.id {
                    HStack {
                        TextField("Template title", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            store.renameCustomHouseRulesPreset(preset, to: renameText)
                            renamingPresetID = nil
                        }
                        Button("Cancel") { renamingPresetID = nil }
                    }
                }

                ScrollView {
                    Text(preset.body)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .background(Color.black.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))

                if let error = store.houseRulesStateError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.crit)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    if preset.origin == .imported {
                        Button("Rename…") { beginRename(preset) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.inkDim)
                        Button("Duplicate") {
                            let copy = store.duplicateCustomHouseRulesPreset(preset)
                            selectedPresetID = copy.id
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.inkDim)
                        Button("Delete", role: .destructive) { pendingDelete = preset }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.crit)
                    }

                    Spacer()

                    Button("Use as Draft") {
                        store.useHouseRulesPresetAsDraft(preset)
                        onUseDraft()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 7)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(18)
        } else {
            Text("Select a template to preview it.")
                .foregroundStyle(Theme.inkDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func beginRename(_ preset: HouseRulesPreset) {
        selectedPresetID = preset.id
        renameText = preset.title
        renamingPresetID = preset.id
    }
}
