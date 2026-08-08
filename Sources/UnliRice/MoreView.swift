import SwiftUI
import UnliRiceCore

/// Central hub view for all relocated secondary features behind "More".
struct MoreView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedDestination: MoreDestination = .setup

    enum MoreDestination: String, CaseIterable, Identifiable {
        case setup = "Setup & Tools"
        case whyNotTextFile = "Why not just a text file?"
        case profiles = "Separate memories"
        case houseRules = "What your AI should always do"
        case folder = "The folder your AI can read"
        case automation = "What Runs on Its Own"
        case map = "Map"
        case yearSoFar = "Your year so far"
        case trustCenter = "Trust Center"
        case notifications = "Notifications"
        case archived = "Archived Notes"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .setup: return "gearshape.fill"
            case .whyNotTextFile: return "doc.text.magnifyingglass"
            case .profiles: return "person.2.fill"
            case .houseRules: return "text.badge.checkmark"
            case .folder: return "folder.fill"
            case .automation: return "bolt.fill"
            case .map: return "network"
            case .yearSoFar: return "calendar"
            case .trustCenter: return "shield.checkmark.fill"
            case .notifications: return "bell.fill"
            case .archived: return "archivebox.fill"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Destination Selector Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MoreDestination.allCases) { item in
                        Button(action: { selectedDestination = item }) {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11))
                                Text(item.rawValue)
                                    .font(.system(size: 12, weight: selectedDestination == item ? .bold : .regular))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selectedDestination == item ? Theme.accentColor : Theme.textSecondary)
                            .selectedControl(cornerRadius: 6, accent: Theme.accentColor, selected: selectedDestination == item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Theme.bgField.opacity(0.4))

            Divider().opacity(0.15)

            // Content view for selected destination
            Group {
                switch selectedDestination {
                case .setup:
                    SetupView()
                case .whyNotTextFile:
                    WhyNotTextFileView()
                case .profiles:
                    ProfileManagerView()
                case .houseRules:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What your AI should always do")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)

                            Text("Standing instructions read by every connected assistant at session start.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textSecondary)

                            HouseRulesPresetGalleryView {
                                store.reload()
                            }
                        }
                        .padding(20)
                    }
                case .folder:
                    folderSection
                case .automation:
                    AutomationView()
                case .map:
                    mapSection
                case .yearSoFar:
                    RetrospectiveView()
                case .trustCenter:
                    TrustCenterView()
                case .notifications:
                    NoticeCenterView()
                case .archived:
                    archivedNotesSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
    }

    // MARK: - Folder Section (The folder your AI can read & What your AI reads first)

    private var folderSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MirrorExportView()

                Divider().opacity(0.15)

                // What your AI reads first (Memory Capsule)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("WHAT YOUR AI READS FIRST")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("≤ 2,500 chars")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(capsulePreviewText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(6)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bgField)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(16)
                .liquidGlass(cornerRadius: 8)
            }
            .padding(20)
        }
    }

    private var capsulePreviewText: String {
        if let capsuleNote = store.notes.first(where: { $0.title.lowercased() == "memory: capsule" }) {
            return capsuleNote.body.isEmpty ? "Memory capsule note is empty." : capsuleNote.body
        }
        return "Memory Summary: \(store.activeProfileName)\nTotal Notes: \(store.notes.count)\nNo dedicated 'Memory: capsule' note yet. Connected AIs will summarize session context here automatically."
    }

    // MARK: - Map Section (Map + Index a folder action)

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Map")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: {
                    store.chooseScanRoot()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text("Index a folder")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.accentColor)
                    .solidControl(cornerRadius: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            NoteGraphView()
        }
    }

    // MARK: - Archived Notes Section

    private var archivedNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Archived Notes (\(store.archivedNotes.count))")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !store.archiveSelection.isEmpty {
                    Button("Restore Selected") {
                        for id in store.archiveSelection {
                            if let note = store.note(id: id) {
                                store.unarchive(note)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            if store.archivedNotes.isEmpty {
                Text("No archived notes.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(20)
                Spacer()
            } else {
                let archived = store.archivedNotes
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(archived, id: \.id) { note in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(note.body)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Restore") {
                                    store.unarchive(note)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.accentColor)
                            }
                            .padding(10)
                            .background(Theme.bgField)
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}
