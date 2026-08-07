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

    @MainActor
    public init(store: CaptureStore? = nil) {
        _store = StateObject(wrappedValue: store ?? CaptureStore())
    }

    public var body: some View {
        VStack(spacing: 12) {
            header
            tabBar


            if store.layoutPlacement == .micTopNotesBottom {
                recordSection
                Divider()
                notesAndCapturesSection
            } else {
                notesAndCapturesSection
                Divider()
                recordSection
            }
        }
        .padding(16)
        .sheet(isPresented: $showSettings) {
            settingsSheet
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
            HStack(spacing: 12) {
                ForEach(store.projectTabs, id: \.self) { tab in
                    Text(tab)
                        .font(.system(size: 13, weight: store.currentProjectTab == tab ? .bold : .medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(store.currentProjectTab == tab ? Color.accentColor : Color.secondary.opacity(0.1))
                        .foregroundColor(store.currentProjectTab == tab ? .white : .primary)
                        .cornerRadius(16)
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accentColor)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Unli Rice")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                Text("Voice Capture & Memory")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { store.sync() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
    }

    private var recordSection: some View {
        VStack(spacing: 10) {
            recordButton
            statusView
        }
        .frame(maxHeight: 160)
    }

    private var recordButton: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red : Color.accentColor)
                .frame(width: 68, height: 68)
            Image(systemName: isRecording ? "square.fill" : "mic.fill")
                .font(.system(size: 26))
                .foregroundColor(.white)
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
        VStack(spacing: 4) {
            switch store.state {
            case .idle:
                Text(store.recordingMode == .holdToRecord ? "Press and hold mic to record" : "Tap mic to record a thought")
                    .font(.system(size: 12.5))
                    .foregroundColor(.secondary)
            case .recording:
                Text(store.recordingMode == .holdToRecord ? "Recording… Release to finish" : "Recording… Tap to finish")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.red)
            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing voice note…")
                        .font(.system(size: 12.5))
                }
            case .completed(let title):
                Text("Saved: “\(title)”")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.green)
            case .error(let msg):
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if !store.partialTranscript.isEmpty && store.state != .idle {
                Text(store.partialTranscript)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    private var notesAndCapturesSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pulledNotesSection
                if !store.pulledNotes.isEmpty && !store.captures.isEmpty {
                    Divider()
                }
                capturesList
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pulledNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Synced with Vault Notes (\(store.pulledNotes.count))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if store.pulledNotes.isEmpty {
                Text("No synced notes found.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.pulledNotes) { note in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .lineLimit(2)
                                if !note.body.isEmpty {
                                    Text(note.body)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            Spacer()
                            Button(action: { store.deleteCapture(id: note.id) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.8))
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var capturesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On-Device Captures (\(store.captures.count))")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)

            if store.captures.isEmpty {
                Text("No local captures recorded yet.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 6) {
                    ForEach(store.captures) { item in
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { store.deleteCapture(id: item.id) }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.8))
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Sync Configuration")) {
                    Button(action: { showFileImporter = true }) {
                        HStack {
                            Text("Select Sync Folder")
                                .foregroundColor(.primary)
                            Spacer()
                            if store.sharedFolderURL != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    if let url = store.sharedFolderURL {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Recording Behavior")) {
                    Picker("Recording Mode", selection: $store.recordingMode) {
                        ForEach(RecordingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Interface Layout")) {
                    Picker("Layout Placement", selection: $store.layoutPlacement) {
                        ForEach(LayoutPlacement.allCases) { placement in
                            Text(placement.rawValue).tag(placement)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Capture Settings")

            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
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
