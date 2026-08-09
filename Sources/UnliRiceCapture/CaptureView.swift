import SwiftUI
import UnliRiceCore
import UniformTypeIdentifiers

public struct CaptureView: View {
    @StateObject private var store: CaptureStore
    @State private var showSettings = false
    @State private var showFileImporter = false
    @State private var showNewTabAlert = false
    @State private var newTabName = ""
    @State private var tabToDelete: String? = nil
    @State private var showDeleteTabAlert = false
    @State private var showAISharePreview = false

    @MainActor
    public init(store: CaptureStore? = nil) {
        _store = StateObject(wrappedValue: store ?? CaptureStore())
    }

    public var body: some View {
        ZStack {
            Theme.bgMain
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                tabBar

                if store.layoutPlacement == .micTopNotesBottom {
                    recordSection
                    Divider().overlay(Theme.borderLight)
                    notesAndCapturesSection
                } else {
                    notesAndCapturesSection
                    Divider().overlay(Theme.borderLight)
                    recordSection
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showAISharePreview) {
            AISharePreviewView(notes: store.selectedNotes) {
                showAISharePreview = false
                store.clearNoteSelection()
            }
        }
        .alert("New Project Tab", isPresented: $showNewTabAlert) {
            TextField("Project Name", text: $newTabName)
            Button("Cancel", role: .cancel) { newTabName = "" }
            Button("Create") {
                if !newTabName.isEmpty && !store.projectTabs.contains(newTabName) {
                    store.projectTabs.append(newTabName)
                    store.currentProjectTab = newTabName
                }
                newTabName = ""
            }
        }
        .alert("Archive Tab?", isPresented: $showDeleteTabAlert, presenting: tabToDelete) { tab in
            Button("Cancel", role: .cancel) { tabToDelete = nil }
            Button("Archive", role: .destructive) {
                if let idx = store.projectTabs.firstIndex(of: tab) {
                    store.projectTabs.remove(at: idx)
                    if store.projectTabs.isEmpty {
                        store.projectTabs = ["Unli Thoughts"]
                    }
                    if store.currentProjectTab == tab {
                        store.currentProjectTab = store.projectTabs[0]
                    }
                }
                tabToDelete = nil
            }
        } message: { tab in
            Text("Are you sure you want to archive '\(tab)'? Captures will remain in the vault.")
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.projectTabs, id: \.self) { tab in
                    let isSelected = store.currentProjectTab == tab
                    Text(tab)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.textSecondary)
                        .selectedControl(cornerRadius: 20, accent: Theme.accentColor, selected: isSelected)
                        .onTapGesture {
                            store.currentProjectTab = tab
                        }
                        .onLongPressGesture {
                            tabToDelete = tab
                            showDeleteTabAlert = true
                        }
                }
                
                Button(action: { showNewTabAlert = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accentColor)
                        .padding(8)
                        .background(Theme.accentSoft)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.accentColor.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .padding(.bottom, 2)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Unli Rice")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Text("Voice Capture & Memory")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(action: { store.sync() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .solidControl(cornerRadius: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 38, height: 38)
                    .solidControl(cornerRadius: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }

    private var recordSection: some View {
        VStack(spacing: 14) {
            recordButton
            statusView
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 20)
    }

    private var recordButton: some View {
        ZStack {
            // Ambient outer glow ring
            Circle()
                .fill((isRecording ? Theme.crit : Theme.accentColor).opacity(isRecording ? 0.25 : 0.15))
                .frame(width: 88, height: 88)

            Circle()
                .fill(isRecording ? Theme.crit : Theme.accentColor)
                .frame(width: 68, height: 68)
                .shadow(color: (isRecording ? Theme.crit : Theme.accentColor).opacity(0.4), radius: 10, x: 0, y: 4)

            Image(systemName: isRecording ? "square.fill" : "mic.fill")
                .font(.system(size: 26))
                .foregroundColor(Theme.onAccent)
        }
        .contentShape(Circle())
        .gesture(
            store.recordingMode == .holdToRecord ?
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isRecording {
                        store.startRecording()
                    }
                }
                .onEnded { _ in
                    if isRecording {
                        store.stopAndProcess()
                    }
                }
            : nil
        )
        .onTapGesture {
            if store.recordingMode == .tapToToggle {
                store.toggleRecording()
            }
        }
    }

    private var isRecording: Bool {
        if case .recording = store.state { return true }
        return false
    }

    private var statusView: some View {
        VStack(spacing: 6) {
            switch store.state {
            case .idle:
                Text(store.recordingMode == .holdToRecord ? "Press and hold mic to record" : "Tap mic to record a thought")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            case .recording:
                Text(store.recordingMode == .holdToRecord ? "Recording… Release to finish" : "Recording… Tap to finish")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.crit)
            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing voice note…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                }
            case .completed(let title):
                Text("Saved: “\(title)”")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.emerald)
            case .error(let msg):
                Text(msg)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.crit)
                    .multilineTextAlignment(.center)
            }

            if !store.partialTranscript.isEmpty && store.state != .idle {
                Text(store.partialTranscript)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgField)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderLight, lineWidth: 1))
                    .cornerRadius(10)
            }
        }
    }

    private var notesAndCapturesSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pulledNotesSection
                if !store.pulledNotes.isEmpty && !store.captures.isEmpty {
                    Divider().overlay(Theme.borderLight)
                }
                capturesList
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pulledNotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SYNCED WITH VAULT NOTES (\(store.pulledNotes.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if !store.selectedNoteIDs.isEmpty {
                    Button("Clear") { store.clearNoteSelection() }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accentColor)
                        .buttonStyle(.plain)
                }
            }

            if !store.selectedNoteIDs.isEmpty {
                sendToAIBar
            }

            if store.pulledNotes.isEmpty {
                Text("No synced notes found.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textLight)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.pulledNotes) { note in
                        let isSelected = store.selectedNoteIDs.contains(note.id)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textLight.opacity(0.5))
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
                                    .lineLimit(2)
                                if !note.body.isEmpty {
                                    Text(note.body)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.85) : Theme.textSecondary)
                                        .lineLimit(3)
                                }
                            }
                            Spacer()
                            Button(action: { store.deleteCapture(id: note.id) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.crit)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(cornerRadius: 12, tint: isSelected ? Theme.accentColor : nil)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture { store.toggleNoteSelection(note.id) }
                    }
                }
            }
        }
    }

    /// Appears once ≥1 note is ticked. A blue glass capsule naming exactly what
    /// would be sent, before anything is — the same "show it before it happens"
    /// promise the rest of this app makes for anything that leaves the device.
    private var sendToAIBar: some View {
        let text = ShareToAI.compose(store.selectedNotes)
        let tokens = ShareToAI.estimatedTokens(text)
        return HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
            Text("Send \(store.selectedNoteIDs.count) to AI")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("~\(tokens) tokens")
                .font(.system(size: 10.5, design: .monospaced))
                .opacity(0.75)
        }
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Theme.accentColor))
        .contentShape(Capsule())
        .onTapGesture { showAISharePreview = true }
    }

    private var capturesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ON-DEVICE CAPTURES (\(store.captures.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            if store.captures.isEmpty {
                Text("No local captures recorded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textLight)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.captures) { item in
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundStyle(Theme.accentColor)
                                .font(.system(size: 13))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Button(action: { store.deleteCapture(id: item.id) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.crit)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .cardStyle(cornerRadius: 12)
                    }
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationView {
            ZStack {
                Theme.bgMain
                    .ignoresSafeArea()

                Form {
                    Section(header: Text("Sync Configuration").foregroundStyle(Theme.textSecondary)) {
                        Button(action: { showFileImporter = true }) {
                            HStack {
                                Text("Select Sync Folder")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if store.sharedFolderURL != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.emerald)
                                }
                            }
                        }
                        if let url = store.sharedFolderURL {
                            Text(url.lastPathComponent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Section(header: Text("Recording Behavior").foregroundStyle(Theme.textSecondary)) {
                        Picker("Recording Mode", selection: $store.recordingMode) {
                            ForEach(RecordingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section(header: Text("Interface Layout").foregroundStyle(Theme.textSecondary)) {
                        Picker("Layout Placement", selection: $store.layoutPlacement) {
                            ForEach(LayoutPlacement.allCases) { placement in
                                Text(placement.rawValue).tag(placement)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Capture Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.setSharedFolder(url)
            }
        }
    }
}

