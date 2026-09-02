import SwiftUI
import UIKit
import UnliRiceCore
import UniformTypeIdentifiers

public struct CaptureView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var store: CaptureStore
    @StateObject private var player = CapturePlayer()
    @StateObject private var lock = AppLock.shared
    @State private var showSettings = false
    @State private var showFolderChoice = false
    @State private var showFolderPicker = false
    @State private var showFileImporter = false
    @State private var showNewTabAlert = false
    @State private var newTabName = ""
    @State private var tabToDelete: String? = nil
    @State private var showDeleteTabAlert = false
    @AppStorage("hasSeenWelcomeSplash") private var hasSeenWelcomeSplash = false
    @State private var showWelcomeSplash = false
    @State private var selectedCapture: SentCaptureItem? = nil

    @MainActor
    public init(store: CaptureStore? = nil) {
        // The shared store, so the mic button and the Action Button are two
        // controls over one recording rather than two independent ones.
        _store = StateObject(wrappedValue: store ?? CaptureStore.shared)
    }

    public var body: some View {
        ZStack {
            mainContent

            if lock.isLocked {
                lockScreen
            }

            if showWelcomeSplash {
                WelcomeSplashView {
                    hasSeenWelcomeSplash = true
                    showWelcomeSplash = false
                    showFolderChoice = store.needsSharedFolderChoice
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            Theme.bgMain
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                tabBar

                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) {
                            recordSection
                            ipadInfoCard
                            Spacer(minLength: 0)
                        }
                        .frame(width: 320)

                        Divider().overlay(Theme.borderLight)

                        notesAndCapturesSection
                    }
                } else if store.layoutPlacement == .micTopNotesBottom {
                    recordSection
                    Divider().overlay(Theme.borderLight)
                    notesAndCapturesSection
                } else {
                    notesAndCapturesSection
                    Divider().overlay(Theme.borderLight)
                    recordSection
                }
            }
            .padding(horizontalSizeClass == .regular ? 24 : 16)
        }
        .onAppear {
            store.resyncRecordingState()
            if hasSeenWelcomeSplash {
                showFolderChoice = store.needsSharedFolderChoice
            } else {
                showWelcomeSplash = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // A recording the Action Button started is still running; the mic
            // button has to come back as a stop button, not as a start button
            // that would open a second recording over the live one.
            store.resyncRecordingState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // `willResignActive` rather than `didEnterBackground`, so the
            // content is already covered in the app switcher snapshot.
            lock.lockOnBackground()
        }
        .alert("Where should captures go?", isPresented: $showFolderChoice) {
            Button("Choose a folder") { showFolderPicker = true }
            Button("Keep on this phone only") { store.choosePrivateMode() }
        } message: {
            Text("A shared folder in iCloud Drive is how thoughts reach your Mac. Without one, everything stays on this phone — you can change this later in Settings.")
        }
        // Its own importer, separate from the one inside the settings sheet:
        // presenting a file importer from the root while a sheet is up does not
        // reliably work, and one shared binding would have to serve both.
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { store.setSharedFolder(url) }
            case .failure:
                // Dismissing the picker is not a decision. Leaving the choice
                // unmade means the prompt returns, rather than silently
                // defaulting someone into either sharing or not sharing.
                break
            }
        }
        .onChange(of: store.currentProjectTab) { _, _ in
            // The row that was playing is no longer on screen; audio that keeps
            // going from an invisible row has no stop button.
            player.stop()
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(item: $selectedCapture) { capture in
            NoteDetailView(store: store, capture: capture)
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

            if isRecordingOrPaused {
                recordingControlBar
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .cardStyle(cornerRadius: 20)
    }

    private var ipadInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "ipad.landscape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                Text("iPad Workspace")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("Project: \(store.currentProjectTab)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text("Captures and notes automatically sync with your Mac via your shared iCloud Drive folder.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textLight)
        }
        .padding(14)
        .cardStyle(cornerRadius: 14)
    }

    private var recordingControlBar: some View {
        HStack(spacing: 32) {
            Button(action: {
                if isPaused {
                    store.resumeRecording()
                } else {
                    store.pauseRecording()
                }
            }) {
                VStack(spacing: 4) {
                    Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.accentColor)
                    Text(isPaused ? "Resume" : "Pause")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                store.stopAndProcess()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.crit)
                    Text("Stop & Save")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }

    private var recordButton: some View {
        ZStack {
            // Ambient outer glow ring
            Circle()
                .fill((isRecording ? Theme.crit : (isPaused ? Theme.accentColor : Theme.accentColor)).opacity(isRecordingOrPaused ? 0.25 : 0.15))
                .frame(width: 88, height: 88)

            Circle()
                .fill(isRecording ? Theme.crit : (isPaused ? Theme.accentColor.opacity(0.85) : Theme.accentColor))
                .frame(width: 68, height: 68)
                .shadow(color: (isRecording ? Theme.crit : Theme.accentColor).opacity(0.4), radius: 10, x: 0, y: 4)

            Image(systemName: isRecording ? "pause.fill" : (isPaused ? "play.fill" : "mic.fill"))
                .font(.system(size: 26))
                .foregroundColor(Theme.onAccent)
        }
        .contentShape(Circle())
        .gesture(
            store.recordingMode == .holdToRecord ?
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isRecordingOrPaused {
                        store.startRecording()
                    }
                }
                .onEnded { _ in
                    if isRecording {
                        store.pauseRecording()
                    }
                }
            : nil
        )
        .onTapGesture {
            if store.recordingMode == .tapToToggle && store.appendTargetNoteID == nil {
                store.toggleRecording()
            }
        }
        .disabled(store.appendTargetNoteID != nil)
        .opacity(store.appendTargetNoteID != nil ? 0.5 : 1.0)
    }

    private var isRecording: Bool {
        if case .recording = store.state { return true }
        return false
    }

    private var isPaused: Bool {
        if case .paused = store.state { return true }
        return false
    }

    private var isRecordingOrPaused: Bool {
        isRecording || isPaused
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private var lockScreen: some View {
        ZStack {
            // Opaque, not a blur: an app-switcher snapshot taken over a
            // translucent overlay still shows the note titles underneath, which
            // is the one moment the lock exists to cover.
            Theme.bgMain
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accentColor)

                Text("Unli Rice is locked")
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)

                if let error = lock.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.crit)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: { Task { await lock.unlock() } }) {
                    Text("Unlock with \(lock.biometryLabel)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 22)
                        .background(Theme.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
        // Prompt straight away, so the common case is one glance rather than a
        // tap and then a glance.
        .task { await lock.unlock() }
    }

    private var formattedFootprint: String {
        ByteCountFormatter.string(fromByteCount: store.audioFootprintBytes, countStyle: .file)
    }

    private var statusView: some View {
        VStack(spacing: 6) {
            switch store.state {
            case .idle:
                Text(store.recordingMode == .holdToRecord ? "Press and hold mic to record" : "Tap mic to record a thought")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            case .recording:
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.crit).frame(width: 8, height: 8)
                        Text("Recording… \(formatDuration(store.recordingDuration))")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.crit)
                    }
                    Text(store.recordingMode == .holdToRecord ? "Release to pause" : "Tap mic or pause to pause · Tap stop when done")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            case .paused:
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentColor)
                        Text("Paused · \(formatDuration(store.recordingDuration))")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accentColor)
                    }
                    Text("Tap resume to keep recording into the same note")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
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
                capturesList
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capturesList: some View {
        let items = store.visibleCaptures

        return VStack(alignment: .leading, spacing: 10) {
            Text("\(store.currentProjectTab.uppercased()) (\(items.count))")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)

            if let message = player.errorMessage {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.crit)
            }

            if items.isEmpty {
                Text("Nothing in this project yet. Record a thought and it lands here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textLight)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        captureRow(item)
                    }
                }
            }
        }
    }

    private func captureRow(_ item: SentCaptureItem) -> some View {
        let isPlaying = player.isPlaying(noteID: item.id)
        let hasAudio = item.audioURL != nil

        return HStack(spacing: 10) {
            Button(action: { player.toggle(noteID: item.id, audioURL: item.audioURL) }) {
                Image(systemName: isPlaying ? "stop.circle.fill" : (hasAudio ? "play.circle.fill" : "waveform"))
                    .font(.system(size: 22))
                    .foregroundStyle(hasAudio ? Theme.accentColor : Theme.textLight)
            }
            .buttonStyle(.plain)
            .disabled(!hasAudio)
            // The recording is gone, the thought is not — retention prunes audio
            // and leaves the note. Saying so beats a button that does nothing.
            .accessibilityLabel(hasAudio ? (isPlaying ? "Stop playback" : "Play recording") : "Recording no longer stored")

            Button(action: { selectedCapture = item }) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: {
                if isPlaying { player.stop() }
                store.archiveCapture(id: item.id)
            }) {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive note")

            Button(action: {
                // Deleting the note deletes the file underneath the player.
                if isPlaying { player.stop() }
                store.deleteCapture(id: item.id)
            }) {
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

    private var settingsSheet: some View {
        NavigationView {
            ZStack {
                Theme.bgMain
                    .ignoresSafeArea()

                Form {
                    Section(header: Text("Vault & Archive").foregroundStyle(Theme.textSecondary)) {
                        NavigationLink(destination: ArchivedNotesView(store: store)) {
                            HStack {
                                Text("Archived Notes")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(store.archivedCaptures.count)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

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
                            Button(role: .destructive, action: {
                                store.choosePrivateMode()
                            }) {
                                Text("Stop syncing — keep on this phone")
                            }
                        } else {
                            Text("Private. Nothing leaves this phone.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Section {
                        Toggle("Require \(lock.biometryLabel)", isOn: $lock.isEnabled)
                            .disabled(!lock.isAvailable)
                        if !lock.isAvailable {
                            Text("Set a passcode on this iPhone first — there is nothing to unlock with until you do.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        // The switch turning itself back off needs its reason
                        // shown *here*. It was only on the lock screen, which
                        // that same failure dismisses — so the user saw a toggle
                        // silently refuse to stay on, with no explanation.
                        if let error = lock.lastError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.crit)
                        }
                    } header: {
                        Text("Privacy").foregroundStyle(Theme.textSecondary)
                    } footer: {
                        Text("Locks the app when it goes to the background. This hides your notes from someone holding your unlocked phone; it is not extra encryption on top of what iOS already does.")
                            .foregroundStyle(Theme.textLight)
                    }

                    Section(header: Text("Recording Behavior").foregroundStyle(Theme.textSecondary)) {
                        Picker("Recording Mode", selection: $store.recordingMode) {
                            ForEach(RecordingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        NavigationLink(destination: TranscriptionLanguageListView(store: store)) {
                            HStack {
                                Text("Language")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(store.transcriptionLocaleID.isEmpty ? "Follow system" : (Locale.current.localizedString(forIdentifier: store.transcriptionLocaleID) ?? store.transcriptionLocaleID))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    } header: {
                        Text("Transcription").foregroundStyle(Theme.textSecondary)
                    } footer: {
                        Text("Transcription runs entirely on your device. Language models download once on demand. Mixed-language speech (like code-switching) is not supported — speech is transcribed using the selected language.")
                            .foregroundStyle(Theme.textLight)
                    }

                    Section {
                        NavigationLink(destination: ReposSnapshotView(store: store)) {
                            Text("Repos on your Mac")
                                .foregroundStyle(Theme.textPrimary)
                        }
                    } header: {
                        Text("From your Mac").foregroundStyle(Theme.textSecondary)
                    } footer: {
                        Text("A read-only picture of your Mac's branches, published to the "
                             + "shared folder. This phone has no repositories and cannot "
                             + "change anything.")
                            .foregroundStyle(Theme.textLight)
                    }

                    Section(header: Text("Interface Layout").foregroundStyle(Theme.textSecondary)) {
                        Picker("Layout Placement", selection: $store.layoutPlacement) {
                            ForEach(LayoutPlacement.allCases) { placement in
                                Text(placement.rawValue).tag(placement)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        Picker("Keep recordings", selection: $store.audioRetention) {
                            ForEach(AudioRetention.allCases) { policy in
                                Text(policy.rawValue).tag(policy)
                            }
                        }
                        HStack {
                            Text("Audio stored")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(formattedFootprint)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } header: {
                        Text("Recordings").foregroundStyle(Theme.textSecondary)
                    } footer: {
                        Text("Audio is roughly 30MB an hour. Pruning it frees the space and keeps the transcript — the note stays, only the recording goes.")
                            .foregroundStyle(Theme.textLight)
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
        .onAppear {
            store.loadAvailableLocalesIfNeeded()
        }
    }
}

