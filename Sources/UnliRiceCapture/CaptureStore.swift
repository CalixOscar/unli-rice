import Foundation
import SwiftUI
import UnliRiceCore

public struct SentCaptureItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let timestamp: Date
    /// Nil once retention has pruned the recording, or on a capture restored
    /// from the log whose audio file is gone. The note outlives its audio.
    public let audioURL: URL?
    /// The project tabs this capture belongs to. Without it every tab showed
    /// every capture, because the list was rendered unfiltered.
    public let tags: [String]

    public init(id: UUID, title: String, timestamp: Date, audioURL: URL?, tags: [String] = []) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.audioURL = audioURL
        self.tags = tags
    }
}

public enum RecordingMode: String, Codable, CaseIterable, Identifiable {
    case tapToToggle = "Tap to toggle"
    case holdToRecord = "Hold to record"
    public var id: String { rawValue }
}

public enum LayoutPlacement: String, Codable, CaseIterable, Identifiable {
    case micTopNotesBottom = "Mic Top, Notes Bottom"
    case micBottomNotesTop = "Mic Bottom, Notes Top"
    public var id: String { rawValue }
}

@MainActor
public final class CaptureStore: ObservableObject {
    /// The store the app and the Action Button intent both work through.
    ///
    /// `RecordCaptureIntent` runs in this process, and a recording it starts has
    /// to be visible to the UI and stoppable from it. A second store would open
    /// a second `EventStore` on the same log — two write queues, one file — and
    /// would leave the on-screen state lying about whether the mic was live.
    public static let shared = CaptureStore()

    public enum State: Equatable {
        case idle
        case recording(audioURL: URL)
        case paused(audioURL: URL)
        case transcribing(audioURL: URL)
        case completed(title: String)
        case error(String)
    }

    private static let recordingModeKey = "UnliRiceCapture_recordingMode"
    private static let layoutPlacementKey = "UnliRiceCapture_layoutPlacement"
    private static let projectTabsKey = "UnliRiceCapture_projectTabs"
    private static let currentProjectTabKey = "UnliRiceCapture_currentProjectTab"
    private static let audioRetentionKey = "UnliRiceCapture_audioRetention"

    @Published public var state: State = .idle
    @Published public var partialTranscript: String = ""
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var captures: [SentCaptureItem] = []
    @Published public var archivedCaptures: [SentCaptureItem] = []
    @Published public var pulledNotes: [Note] = []
    @Published public var sharedFolderURL: URL?

    private var durationTimer: Timer?

    @Published public var audioRetention: AudioRetention {
        didSet {
            UserDefaults.standard.set(audioRetention.rawValue, forKey: Self.audioRetentionKey)
            sweepExpiredAudio()
        }
    }

    /// The captures belonging to the tab on screen.
    ///
    /// A tab is only a folder if the list respects it. `capturesList` rendered
    /// `captures` directly, so creating a new tab produced a new name over the
    /// same, complete list of every recording ever made — which is what "the
    /// notes stay on screen in the same folder" was.
    public var visibleCaptures: [SentCaptureItem] {
        captures.filter { $0.tags.contains(currentProjectTab) }
    }

    /// Where recordings live. Also the unit retention operates on.
    public var audioDirectory: URL {
        storageDir.appendingPathComponent("Audio", isDirectory: true)
    }

    public var audioFootprintBytes: Int64 {
        AudioRetention.audioFootprint(audioDirectory: audioDirectory)
    }

    @Published public var recordingMode: RecordingMode {
        didSet {
            UserDefaults.standard.set(recordingMode.rawValue, forKey: Self.recordingModeKey)
        }
    }

    @Published public var layoutPlacement: LayoutPlacement {
        didSet {
            UserDefaults.standard.set(layoutPlacement.rawValue, forKey: Self.layoutPlacementKey)
        }
    }

    @Published public var projectTabs: [String] {
        didSet {
            UserDefaults.standard.set(projectTabs, forKey: Self.projectTabsKey)
        }
    }

    @Published public var currentProjectTab: String {
        didSet {
            UserDefaults.standard.set(currentProjectTab, forKey: Self.currentProjectTabKey)
            // Filter pulledNotes based on the current tab when switching
            updatePulledNotesForCurrentTab()
        }
    }

    private let recorder: Recorder
    private let transcriber: Transcriber
    private let shardWriter: ShardWriter
    private let storageDir: URL
    private let eventStore: EventStore
    private let noteService: NoteService
    public let deviceIdentity: DeviceIdentity
    private var audioIndex: CaptureAudioIndex

    public init(
        storageDir: URL? = nil,
        transcriber: Transcriber = SpeechAnalyzerTranscriber()
    ) {
        let savedModeRaw = UserDefaults.standard.string(forKey: Self.recordingModeKey) ?? ""
        self.recordingMode = RecordingMode(rawValue: savedModeRaw) ?? .tapToToggle

        let savedLayoutRaw = UserDefaults.standard.string(forKey: Self.layoutPlacementKey) ?? ""
        self.layoutPlacement = LayoutPlacement(rawValue: savedLayoutRaw) ?? .micTopNotesBottom

        let savedTabsRaw = UserDefaults.standard.stringArray(forKey: Self.projectTabsKey) ?? ["Unli Thoughts"]
        let initialTabs = savedTabsRaw.isEmpty ? ["Unli Thoughts"] : savedTabsRaw
        self.projectTabs = initialTabs

        let savedCurrentTab = UserDefaults.standard.string(forKey: Self.currentProjectTabKey) ?? "Unli Thoughts"
        self.currentProjectTab = initialTabs.contains(savedCurrentTab) ? savedCurrentTab : initialTabs[0]

        let savedRetentionRaw = UserDefaults.standard.string(forKey: Self.audioRetentionKey) ?? ""
        self.audioRetention = AudioRetention(rawValue: savedRetentionRaw) ?? .forever

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseDir = storageDir ?? docs.appendingPathComponent("UnliRiceCapture", isDirectory: true)
        self.storageDir = baseDir
        self.recorder = Recorder.shared
        self.transcriber = transcriber

        let identity = DeviceIdentity.current(inDirectory: baseDir)
        self.deviceIdentity = identity

        let logURL = baseDir.appendingPathComponent("events.jsonl")
        var initError: String? = nil
        let store: EventStore
        do {
            store = try EventStore(fileURL: logURL)
        } catch {
            initError = "Failed to initialize event log: \(error.localizedDescription)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID().uuidString).jsonl")
            do {
                store = try EventStore(fileURL: tempURL)
            } catch {
                preconditionFailure("Failed to initialize temporary storage: \(error)")
            }
        }
        self.eventStore = store
        self.noteService = NoteService(store: store, deviceLabel: identity.label)

        let ownShardFile = baseDir.appendingPathComponent("shards", isDirectory: true)
            .appendingPathComponent("events-phone-\(identity.id).jsonl")
        self.shardWriter = ShardWriter(shardFileURL: ownShardFile, deviceLabel: identity.label)

        self.audioIndex = CaptureAudioIndex.load(from: CaptureAudioIndex.url(inDirectory: baseDir))

        self.sharedFolderURL = SharedFolderManager.shared.resolveBookmark()
        if let initError = initError {
            self.state = .error(initError)
        } else {
            sweepExpiredAudio()
            sync()
        }
    }

    /// Rebuilds the on-device list from the event log.
    ///
    /// `captures` used to be in-memory only, appended to as you recorded, so it
    /// emptied on every relaunch — the recordings were still in the log, but the
    /// screen that was meant to show them started blank. Deriving it from the
    /// log also means each capture arrives carrying its tags, which is what
    /// makes a tab behave like a folder.
    private func rebuildCaptures() {
        let notes = (try? noteService.listNotes(includeArchived: true)) ?? []
        let audioDir = audioDirectory

        let allItems = notes
            .sorted { $0.createdAt > $1.createdAt }
            .map { note in
                let audioURL = audioIndex.filename(for: note.id).map {
                    audioDir.appendingPathComponent($0)
                }
                return (
                    archived: note.archived,
                    item: SentCaptureItem(
                        id: note.id,
                        title: note.title,
                        timestamp: note.createdAt,
                        audioURL: audioURL.flatMap {
                            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
                        },
                        tags: Array(note.tags)
                    )
                )
            }

        captures = allItems.filter { !$0.archived }.map { $0.item }
        archivedCaptures = allItems.filter { $0.archived }.map { $0.item }
    }

    public func archiveCapture(id: UUID) {
        try? noteService.archiveNote(id: id, reason: "Archived from iOS capture app", source: "human")
        rebuildCaptures()
        updatePulledNotesForCurrentTab()
        sync()
    }

    public func unarchiveCapture(id: UUID) {
        try? noteService.unarchiveNote(id: id, source: "human")
        rebuildCaptures()
        updatePulledNotesForCurrentTab()
        sync()
    }

    /// Applies the retention policy and drops index entries whose file is gone.
    public func sweepExpiredAudio() {
        audioRetention.sweep(audioDirectory: audioDirectory)

        let stale = audioIndex.noteIDsMissingAudio(inAudioDirectory: audioDirectory)
        guard !stale.isEmpty else { return }
        for noteID in stale {
            audioIndex.forget(noteID: noteID)
        }
        try? audioIndex.save(to: CaptureAudioIndex.url(inDirectory: storageDir))
    }

    /// Whether the user still needs to be asked where captures should go.
    public var needsSharedFolderChoice: Bool {
        !SharedFolderManager.shared.hasChosen
    }

    /// Keeps every capture on this phone.
    ///
    /// Not merely "no folder selected" — `sync()` used to fall back to a local
    /// shards directory when none was set, which happens to stay private but
    /// only by accident, and left the user with no way to say so. This records
    /// the intent, so the prompt stops asking and the UI can state plainly that
    /// nothing leaves the device.
    public func choosePrivateMode() {
        SharedFolderManager.shared.chooseNoFolder()
        sharedFolderURL = nil
        objectWillChange.send()
    }

    /// Forgets the current folder and asks again on next launch.
    public func clearSharedFolder() {
        SharedFolderManager.shared.clearBookmark()
        SharedFolderManager.shared.resetChoice()
        sharedFolderURL = nil
        objectWillChange.send()
    }

    public func setSharedFolder(_ url: URL) {
        do {
            try SharedFolderManager.shared.saveBookmark(for: url)
            self.sharedFolderURL = url

            // Rewinding the cursor republishes the whole log into the new
            // folder. `ShardPublisher` *appends*, so the destination has to be
            // cleared first or every re-pick stacks another full copy of the
            // history on top of the last one — the shard in the shared folder
            // had three of them before this was fixed.
            let ownShardFilename = "events-phone-\(deviceIdentity.id).jsonl"
            let ownShardFileURL = url.appendingPathComponent(ownShardFilename)
            let needsStop = url.startAccessingSecurityScopedResource()
            if FileManager.default.fileExists(atPath: ownShardFileURL.path) {
                try? FileManager.default.removeItem(at: ownShardFileURL)
            }
            if needsStop { url.stopAccessingSecurityScopedResource() }

            let syncStateURL = SyncState.url(besideEventLog: storageDir.appendingPathComponent("events.jsonl"))
            var syncState = SyncState.load(from: syncStateURL)
            syncState.publishedCursor = nil
            try? syncState.save(to: syncStateURL)

            sync()
        } catch {
            state = .error("Failed to save shared folder bookmark: \(error.localizedDescription)")
        }
    }

    public func sync() {
        let syncFolder = sharedFolderURL ?? storageDir.appendingPathComponent("shards", isDirectory: true)
        let needsStop = syncFolder.startAccessingSecurityScopedResource()
        defer { if needsStop { syncFolder.stopAccessingSecurityScopedResource() } }

        let syncStateURL = SyncState.url(besideEventLog: storageDir.appendingPathComponent("events.jsonl"))
        let ownShardFilename = "events-phone-\(deviceIdentity.id).jsonl"

        _ = try? ShardImporter.importShards(
            from: syncFolder,
            into: eventStore,
            syncStateURL: syncStateURL,
            ownShardFilename: ownShardFilename
        )

        noteService.rebuild()
        updatePulledNotesForCurrentTab()
        rebuildCaptures()

        let ownShardFileURL = syncFolder.appendingPathComponent(ownShardFilename)
        let ownDeviceLabel = deviceIdentity.label
        _ = try? ShardPublisher.publishLocalEvents(
            eventLogURL: storageDir.appendingPathComponent("events.jsonl"),
            to: ownShardFileURL,
            syncStateURL: syncStateURL,
            ownDeviceLabel: ownDeviceLabel,
            isLocallyOriginated: { event in
                // Phone publishes events originated on this phone (device == phoneDeviceLabel).
                // Imported Mac events have device == nil or device == macDeviceLabel, so they are filtered out.
                event.device == ownDeviceLabel
            }
        )
    }

    public func updatePulledNotesForCurrentTab() {
        let allNotes = (try? noteService.listNotes()) ?? []
        self.pulledNotes = allNotes.filter { note in
            note.tags.contains(currentProjectTab)
        }
    }

    public func deleteCapture(id: UUID) {
        captures.removeAll { $0.id == id }
        pulledNotes.removeAll { $0.id == id }

        // Purging the note without its recording leaves the audio orphaned on
        // disk forever — nothing else references it, so nothing else can ever
        // clean it up.
        if let filename = audioIndex.filename(for: id) {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(filename))
            audioIndex.forget(noteID: id)
            try? audioIndex.save(to: CaptureAudioIndex.url(inDirectory: storageDir))
        }

        let logURL = storageDir.appendingPathComponent("events.jsonl")
        if FileManager.default.fileExists(atPath: logURL.path) {
            _ = try? TrashService.purge(noteIDs: [id], logURL: logURL)
        }

        let ownShardFilename = "events-phone-\(deviceIdentity.id).jsonl"
        let syncFolder = sharedFolderURL ?? storageDir.appendingPathComponent("shards", isDirectory: true)
        let ownShardFileURL = syncFolder.appendingPathComponent(ownShardFilename)

        // Remove the target published shard file so ShardPublisher rebuilds it cleanly from logURL
        if FileManager.default.fileExists(atPath: ownShardFileURL.path) {
            try? FileManager.default.removeItem(at: ownShardFileURL)
        }

        let syncStateURL = SyncState.url(besideEventLog: logURL)
        var syncState = SyncState.load(from: syncStateURL)
        syncState.publishedCursor = nil
        try? syncState.save(to: syncStateURL)

        let ownDeviceLabel = deviceIdentity.label
        _ = try? ShardPublisher.publishLocalEvents(
            eventLogURL: logURL,
            to: ownShardFileURL,
            syncStateURL: syncStateURL,
            ownDeviceLabel: ownDeviceLabel,
            isLocallyOriginated: { event in
                event.device == ownDeviceLabel
            }
        )

        sync()
    }

    public func toggleRecording() {
        switch state {
        case .idle, .completed, .error:
            startRecording()
        case .recording:
            pauseRecording()
        case .paused:
            resumeRecording()
        case .transcribing:
            break
        }
    }

    public func startRecording() {
        Task {
            do {
                let audioURL = try await recorder.startRecording(
                    outputDirectory: storageDir.appendingPathComponent("Audio")
                )
                recordingDuration = 0
                startDurationTimer()
                state = .recording(audioURL: audioURL)
                partialTranscript = "Recording audio…"
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    public func pauseRecording() {
        if case .recording(let url) = state {
            recorder.pauseRecording()
            state = .paused(audioURL: url)
            partialTranscript = "Recording paused. Tap resume or stop."
        }
    }

    public func resumeRecording() {
        if case .paused(let url) = state {
            recorder.resumeRecording()
            state = .recording(audioURL: url)
            partialTranscript = "Recording audio…"
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .recording = self.state {
                    self.recordingDuration += 1
                }
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    public func stopAndProcess() {
        Task { _ = try? await finishRecording() }
    }

    /// Stops the recording and returns the title it was saved under.
    ///
    /// The awaitable form exists for `RecordCaptureIntent`, which has to tell
    /// the user what it saved before `perform()` returns. The fire-and-forget
    /// `stopAndProcess()` above wraps it for the UI, which learns the outcome
    /// from `state` instead.
    @discardableResult
    public func finishRecording() async throws -> String {
        stopDurationTimer()
        guard let audioURL = recorder.stopRecording() else {
            state = .error("No audio file recorded.")
            throw RecorderError.recordingFailed("No audio file recorded.")
        }

        state = .transcribing(audioURL: audioURL)
        partialTranscript = "Transcribing audio..."

        do {
                let transcript = try await transcriber.transcribe(audioURL: audioURL)
                let written = try shardWriter.writeCaptureEvents(transcript: transcript, tags: [currentProjectTab])
                guard let event = written.first else {
                    throw RecorderShardError.nothingWritten
                }

                // Also append to local eventStore on phone. Every event, not
                // just the `created` one: `sync()` republishes from this log, so
                // an event missing here never reaches the shared folder and
                // never reaches the Mac. Dropping the `tagged` events here is
                // what left captures untagged, which made the project-tab filter
                // in `updatePulledNotesForCurrentTab` match nothing and showed
                // "No synced notes found." over a corpus that had them.
                let jsonEncoder = JSONEncoder()
                jsonEncoder.dateEncodingStrategy = .iso8601
                for written in written {
                    if let rawData = try? jsonEncoder.encode(written) {
                        try? eventStore.appendRaw(rawData)
                    }
                }

                // Keyed by note, not event: the note is what the list renders and
                // what playback is asked for. `event.id` is the *created event's*
                // id, which is a different UUID and never appears again.
                audioIndex.record(noteID: event.noteId, filename: audioURL.lastPathComponent)
                try? audioIndex.save(to: CaptureAudioIndex.url(inDirectory: storageDir))

                let item = SentCaptureItem(
                    id: event.noteId,
                    title: event.title ?? ShardWriter.timestampedFallbackTitle(for: event.timestamp),
                    timestamp: event.timestamp,
                    audioURL: audioURL,
                    tags: [currentProjectTab]
                )
                captures.insert(item, at: 0)
                state = .completed(title: item.title)
                partialTranscript = transcript

                // Sync after capture
                sync()
                return item.title
        } catch {
            state = .error("Transcription failed: \(error.localizedDescription) (audio saved at \(audioURL.lastPathComponent))")
            throw error
        }
    }

    /// One press of the Action Button: start if idle, stop and save if a
    /// recording is already running. Returns what to say back to the user.
    ///
    /// The intent used to `Task.sleep` for three seconds and stop itself, which
    /// made the button useless for its actual purpose — a thought you have not
    /// finished saying in three seconds was simply cut off, with the truncated
    /// half saved as if it were the whole thing.
    public func toggleFromIntent() async -> String {
        if recorder.isRecording {
            do {
                let title = try await finishRecording()
                return "Saved: “\(title)”"
            } catch {
                return "Could not save that recording: \(error.localizedDescription)"
            }
        }

        do {
            let audioURL = try await recorder.startRecording(
                outputDirectory: audioDirectory
            )
            state = .recording(audioURL: audioURL)
            partialTranscript = "Recording audio…"
            return "Recording. Press again to stop."
        } catch {
            state = .error(error.localizedDescription)
            return error.localizedDescription
        }
    }

    /// Re-reads the mic state into the UI.
    ///
    /// A recording started by the Action Button while the app was closed leaves
    /// `state` at `.idle` when the app is opened, which would show a mic button
    /// that starts a *second* recording instead of a stop button for the live
    /// one.
    public func resyncRecordingState() {
        if recorder.isRecording, let url = recorder.currentAudioURL {
            if recorder.isPaused {
                state = .paused(audioURL: url)
                partialTranscript = "Recording paused. Tap resume or stop."
            } else if case .recording = state {
                // Already recording
            } else {
                state = .recording(audioURL: url)
                partialTranscript = "Recording audio…"
            }
        } else if case .recording = state {
            state = .idle
            stopDurationTimer()
        } else if case .paused = state {
            state = .idle
            stopDurationTimer()
        }
    }
}
