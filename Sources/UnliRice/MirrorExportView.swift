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
                    .font(.system(size: 20, weight: .semibold, design: .serif))
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
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            triggerExport()
        }
    }

    private var exportFolderURL: URL {
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
                houseRulesText: store.houseRulesText
            )
            exportResult = res
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}
