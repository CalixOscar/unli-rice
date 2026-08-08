import UnliRiceCore
import SwiftUI
import AppKit

/// Displays state and controls for the plain-markdown Mirror Export folder per profile.
struct MirrorExportView: View {
    @EnvironmentObject var store: AppStore
    @State private var exportResult: MirrorExporter.ExportResult?
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Mirror Export (Universal Read Channel)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("A derived plain-markdown folder that any LLM or tool can read directly with zero setup.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Export Info Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accentColor)
                    Text("Export Directory")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let result = exportResult {
                        Text("Regenerated \(result.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text(exportFolderURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.brass)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgField)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("Derived files automatically included:\n• 00_Index.md, 01_Identity.md, 02_Voice.md, 03_Principles.md, 04_Guardrails.md\n• 05+_Overlay_<Name>.md (one per overlay)\n• PROJECTS/ (one file per Project: note)\n• MEMORY.md (capsule ≤2,500 chars)\n• HOUSE_RULES.md (current active rules)\n• RAW/ (ingested raw transcripts & documents)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)

                if let result = exportResult {
                    HStack(spacing: 12) {
                        Text("\(result.exportedFilesCount) files exported")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.emerald)

                        if let len = result.memoryCapsuleLength {
                            Text("MEMORY.md: \(len) / 2,500 chars")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(result.memoryCapsuleExceeded ? Theme.crit : Theme.textSecondary)
                        }
                    }
                }

                if let error = exportError {
                    Text("Export error: \(error)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.crit)
                }

                HStack(spacing: 10) {
                    Button("Export Now") {
                        triggerExport()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: exportFolderURL.path)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(Theme.onSolidFill)
                    .solidControl(cornerRadius: 4)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .liquidGlass(cornerRadius: 8)

            // Copy Context Card for ChatGPT web
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy Context for ChatGPT & Web LLMs")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("One click to copy your guardrails, project context, and memory capsule for browser chats.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    if projectNotes.isEmpty {
                        Button("Copy Context to Clipboard") {
                            copyContext(projectNote: nil)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.onSolidFill)
                        .solidControl(cornerRadius: 4)
                    } else {
                        Menu {
                            Button("Copy Guardrails + Memory (No Project)") {
                                copyContext(projectNote: nil)
                            }
                            Divider()
                            ForEach(projectNotes, id: \.id) { note in
                                Button("Copy Context for \(note.title)") {
                                    copyContext(projectNote: note)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Copy Context for…")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(Theme.onSolidFill)
                        }
                        .menuStyle(.borderlessButton)
                        .solidControl(cornerRadius: 4)
                    }

                    if let notice = copiedNotice {
                        Text(notice)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.emerald)
                    }
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            triggerExport()
        }
    }

    @State private var copiedNotice: String?

    private var projectNotes: [Note] {
        let prefix = "project: "
        return store.notes
            .filter { $0.title.lowercased().hasPrefix(prefix) }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    private func copyContext(projectNote: Note?) {
        var sections: [String] = []

        if let guardrails = store.notes.first(where: { $0.title.lowercased() == "profile: guardrails" }) {
            sections.append("## Guardrails & Memory Conventions\n\n\(guardrails.body)")
        }

        if let proj = projectNote {
            sections.append("## Project Context (\(proj.title))\n\n\(proj.body)")
        }

        if let capsule = store.notes.first(where: { $0.title.lowercased() == "memory: capsule" }) {
            sections.append("## Memory Capsule\n\n\(capsule.body)")
        }

        let fullText = sections.joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)

        copiedNotice = "✓ Copied context to clipboard"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            copiedNotice = nil
        }
    }

    private var exportFolderURL: URL {
        if let custom = store.exportFolderURL {
            return custom
        }
        let vaultFolderURL = store.dataURL.deletingLastPathComponent()
        let safeName = store.activeProfileName.replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespaces)
        return vaultFolderURL.deletingLastPathComponent().appendingPathComponent("\(safeName) Export", isDirectory: true)
    }

    private func triggerExport() {
        let vaultFolderURL = store.dataURL.deletingLastPathComponent()
        do {
            let res = try MirrorExporter.exportMirror(
                profileName: store.activeProfileName,
                vaultFolderURL: vaultFolderURL,
                noteService: store.service,
                houseRulesText: store.houseRulesText,
                customExportDirectory: store.exportFolderURL
            )
            exportResult = res
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}
