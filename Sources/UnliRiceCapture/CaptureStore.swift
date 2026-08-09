import Foundation
import SwiftUI
import UnliRiceCore

public struct SentCaptureItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let timestamp: Date
    public let audioURL: URL

    public init(id: UUID, title: String, timestamp: Date, audioURL: URL) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.audioURL = audioURL
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
    public enum State: Equatable {
        case idle
        case recording(audioURL: URL)
        case transcribing(audioURL: URL)
        case completed(title: String)
        case error(String)
    }

    private static let recordingModeKey = "UnliRiceCapture_recordingMode"
    private static let layoutPlacementKey = "UnliRiceCapture_layoutPlacement"
    private static let projectTabsKey = "UnliRiceCapture_projectTabs"
    private static let currentProjectTabKey = "UnliRiceCapture_currentProjectTab"

    @Published public var state: State = .idle
    @Published public var partialTranscript: String = ""
    @Published public var captures: [SentCaptureItem] = []
    @Published public var pulledNotes: [Note] = []
    @Published public var sharedFolderURL: URL?

    /// Which of `pulledNotes` are ticked for "Send to AI". Selecting is not
    /// sending — nothing is composed or shared until the user acts on it.
    @Published public var selectedNoteIDs: Set<UUID> = []

    public var selectedNotes: [Note] {
        pulledNotes.filter { selectedNoteIDs.contains($0.id) }
    }

    public func toggleNoteSelection(_ id: UUID) {
        if selectedNoteIDs.contains(id) {
            selectedNoteIDs.remove(id)
        } else {
            selectedNoteIDs.insert(id)
        }
    }

    public func clearNoteSelection() {
        selectedNoteIDs.removeAll()
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

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseDir = storageDir ?? docs.appendingPathComponent("UnliRiceCapture", isDirectory: true)
        self.storageDir = baseDir
        self.recorder = Recorder()
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

        self.sharedFolderURL = SharedFolderManager.shared.resolveBookmark()
        if let initError = initError {
            self.state = .error(initError)
        } else {
            sync()
        }
    }

    public func setSharedFolder(_ url: URL) {
        do {
            try SharedFolderManager.shared.saveBookmark(for: url)
            self.sharedFolderURL = url
            
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
        // A note that's out of view (switched tabs, deleted, no longer synced)
        // must not stay silently selected — the "N selected" count on screen
        // has to mean N notes actually in front of you right now.
        let visible = Set(pulledNotes.map(\.id))
        selectedNoteIDs = selectedNoteIDs.intersection(visible)
    }

    public func deleteCapture(id: UUID) {
        captures.removeAll { $0.id == id }
        pulledNotes.removeAll { $0.id == id }

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
            stopAndProcess()
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
                state = .recording(audioURL: audioURL)
                partialTranscript = "Recording audio…"
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    public func stopAndProcess() {
        guard let audioURL = recorder.stopRecording() else {
            state = .error("No audio file recorded.")
            return
        }

        state = .transcribing(audioURL: audioURL)
        partialTranscript = "Transcribing audio..."

        Task {
            do {
                let transcript = try await transcriber.transcribe(audioURL: audioURL)
                let event = try shardWriter.writeCapture(transcript: transcript, tags: [currentProjectTab])

                // Also append to local eventStore on phone
                let jsonEncoder = JSONEncoder()
                jsonEncoder.dateEncodingStrategy = .iso8601
                if let rawData = try? jsonEncoder.encode(event) {
                    try? eventStore.appendRaw(rawData)
                }

                let item = SentCaptureItem(
                    id: event.id,
                    title: event.title ?? ShardWriter.timestampedFallbackTitle(for: event.timestamp),
                    timestamp: event.timestamp,
                    audioURL: audioURL
                )
                captures.insert(item, at: 0)
                state = .completed(title: item.title)
                partialTranscript = transcript

                // Sync after capture
                sync()
            } catch {
                state = .error("Transcription failed: \(error.localizedDescription) (audio saved at \(audioURL.lastPathComponent))")
            }
        }
    }
}
