import Foundation
import SwiftUI
import UnliRiceCore

/// Why a typed note was refused.
public enum CaptureTextError: Error, LocalizedError {
    case empty
    case captureInFlight

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Nothing to save yet."
        case .captureInFlight:
            return "Finish the recording first — it is still being saved."
        }
    }
}

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
    private static let transcriptionLocaleKey = "UnliRiceCapture_transcriptionLocale"

    @Published public var state: State = .idle
    @Published public var partialTranscript: String = ""
    @Published public var recordingDuration: TimeInterval = 0
    @Published public var captures: [SentCaptureItem] = []
    @Published public var archivedCaptures: [SentCaptureItem] = []
    @Published public var pulledNotes: [Note] = []
    @Published public var sharedFolderURL: URL?
    @Published public var appendTargetNoteID: UUID? = nil

    @Published public var availableLocales: [Locale] = []
    @Published public var localeStatuses: [String: LanguageStatus] = [:]
    @Published public var downloadingLocaleIDs: Set<String> = []

    @Published public var transcriptionLocaleID: String {
        didSet {
            UserDefaults.standard.set(transcriptionLocaleID, forKey: Self.transcriptionLocaleKey)
            let previousID = oldValue
            let newID = transcriptionLocaleID
            Task {
                if !previousID.isEmpty && previousID != newID {
                    await TranscriptionLanguages.release(Locale(identifier: previousID))
                }
                if !newID.isEmpty {
                    do {
                        try await TranscriptionLanguages.reserve(Locale(identifier: newID))
                    } catch {
                        await MainActor.run {
                            self.state = .error(error.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    /// "Follow system" resolves to the user's first KEYBOARD language, not the device's
    /// region setting. `Locale.current` is the display language and was a poor guess at
    /// what someone speaks — an en-PH device with a Filipino keyboard installed was
    /// transcribed as en-PH with no indication the keyboard existed. See `KeyboardLocales`.
    public var effectiveTranscriptionLocale: Locale {
        TranscriptionLocale.effectiveLocale(
            for: transcriptionLocaleID,
            systemDefault: KeyboardLocales.preferred()
        )
    }

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
    public let noteService: NoteService
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

        let savedLocaleID = UserDefaults.standard.string(forKey: Self.transcriptionLocaleKey) ?? ""
        self.transcriptionLocaleID = savedLocaleID

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

    public func loadAvailableLocalesIfNeeded() {
        guard availableLocales.isEmpty else { return }
        Task {
            let locales = await TranscriptionLanguages.supported(preferring: KeyboardLocales.active())
            var statuses: [String: LanguageStatus] = [:]
            for loc in locales {
                statuses[loc.identifier] = await TranscriptionLanguages.status(for: loc)
            }
            await MainActor.run {
                self.availableLocales = locales
                self.localeStatuses = statuses
            }
        }
    }

    public func refreshStatus(for locale: Locale) {
        Task {
            let status = await TranscriptionLanguages.status(for: locale)
            await MainActor.run {
                self.localeStatuses[locale.identifier] = status
            }
        }
    }

    public func downloadLocale(_ locale: Locale) {
        guard !downloadingLocaleIDs.contains(locale.identifier) else { return }
        downloadingLocaleIDs.insert(locale.identifier)
        localeStatuses[locale.identifier] = .downloading
        Task {
            do {
                try await TranscriptionLanguages.install(locale)
                let newStatus = await TranscriptionLanguages.status(for: locale)
                await MainActor.run {
                    self.downloadingLocaleIDs.remove(locale.identifier)
                    self.localeStatuses[locale.identifier] = newStatus
                }
            } catch {
                await MainActor.run {
                    self.downloadingLocaleIDs.remove(locale.identifier)
                    self.localeStatuses[locale.identifier] = .available
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    public func startAppendRecording(targetNoteID: UUID) {
        guard state == .idle else { return }
        appendTargetNoteID = targetNoteID
        startRecording()
    }

    /// Appends text to an existing note, mirroring shard write and local event store.
    public func appendToCapture(noteID: UUID, text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let written = try shardWriter.writeAppendEvents(noteID: noteID, text: trimmed)
        // Same durable-success rule as `saveCapturedText`, and the same reason: the
        // shard is not what `sync()` publishes from. These were `try?`, so an append
        // that never reached the log reported success and then vanished.
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        for writtenEvent in written {
            try eventStore.appendRaw(try jsonEncoder.encode(writtenEvent))
        }

        rebuildCaptures()
        sync()
    }

    /// Append a thought to the one note that belongs to a project, creating it the
    /// first time.
    ///
    /// **The title is the key**, deliberately. Titles are permanent in this codebase —
    /// there is no retitle event, and `Projector.resolveLinks` matches wiki-links by
    /// title precisely because of that — so looking a note up by title cannot disagree
    /// with the corpus the way a stored id-to-project mapping could.
    ///
    /// Uses `.appended` only. No new `EventKind`, and nothing is ever overwritten.
    public func appendToProjectNote(title: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = ((try? noteService.listNotes(includeArchived: true)) ?? [])
            .first { $0.title.caseInsensitiveCompare(title) == .orderedSame }

        do {
            if let note = existing {
                try appendToCapture(noteID: note.id, text: trimmed)
            } else {
                // createNote takes no tags; tagging is its own event, which is why it
                // is a second call rather than a parameter.
                let note = try noteService.createNote(title: title, body: trimmed,
                                                      source: "human")
                _ = try? noteService.tagNote(id: note.id, tag: "repo", source: "human")
                rebuildCaptures()
                sync()
            }
        } catch {
            state = .error("Could not save the note: \(error.localizedDescription)")
        }
    }

    public func archiveTodo(noteID: UUID) {
        _ = try? noteService.archiveNote(id: noteID, reason: "done", source: "human")
        rebuildCaptures()
        sync()
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

    /// True while a spoken capture is in flight — recording, paused, or being
    /// transcribed.
    ///
    /// `.transcribing` belongs here as much as the other two, and that is the whole
    /// point: `finishRecording` spends its entire awaited transcription interval in
    /// that state, so a typed save landing in the window would set `.completed` and
    /// insert an item that the voice continuation then overwrites. The view reads
    /// this rather than deriving its own predicate, so the two cannot disagree.
    public var captureInFlight: Bool {
        switch state {
        case .recording, .paused, .transcribing: return true
        case .idle, .completed, .error: return false
        }
    }

    /// Turn finished text into a note: shard write, local mirror, list entry, sync.
    ///
    /// Extracted from `finishRecording` so a typed note and a spoken one take the
    /// same path. It covers ONLY the normal new-capture branch — a voice append has
    /// a different contract (it appends to an existing note and creates no capture
    /// item) and stays in the caller.
    ///
    /// `audioURL` is nil for a typed note. `SentCaptureItem.audioURL` has always been
    /// optional because a note outlives its audio; a note that never had any is the
    /// same case reached from the other direction.
    @discardableResult
    private func saveCapturedText(_ text: String, audioURL: URL?) throws -> SentCaptureItem {
        let written = try shardWriter.writeCaptureEvents(text: text, tags: [currentProjectTab])
        guard let event = written.first else {
            throw RecorderShardError.nothingWritten
        }

        // **Durable success is defined here: every event in the batch reaches
        // `events.jsonl`.** The shard write above is not it.
        //
        // `shardWriter` writes to `baseDir/shards/`, while `sync()` publishes from
        // `events.jsonl` into the SHARED folder — so once a shared folder is
        // configured the shard write is a dead end and this log is the only route
        // to the Mac. Both of these writes used to be `try?`, which meant a failure
        // here left the note absent from the Mac forever and gone from the phone at
        // the next `rebuildCaptures()`, while the caller was told it had saved.
        //
        // Every event, not just the `created` one: dropping the `tagged` events is
        // what left captures untagged, so the project-tab filter matched nothing and
        // the list said "No synced notes found." over a corpus that had them.
        //
        // No rollback on a partial failure. The log is append-only and nothing
        // rewrites it; the events already written stay and the error says what
        // happened.
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        for writtenEvent in written {
            try eventStore.appendRaw(try jsonEncoder.encode(writtenEvent))
        }

        // Best-effort, and deliberately NOT part of durable success: losing the
        // index costs playback of one recording, not the note. Keyed by note, not
        // event — `event.id` is the created event's id and never appears again.
        // Never index a file that does not exist.
        if let audioURL {
            audioIndex.record(noteID: event.noteId, filename: audioURL.lastPathComponent)
            try? audioIndex.save(to: CaptureAudioIndex.url(inDirectory: storageDir))
        }

        let item = SentCaptureItem(
            id: event.noteId,
            title: event.title ?? ShardWriter.timestampedFallbackTitle(for: event.timestamp),
            timestamp: event.timestamp,
            audioURL: audioURL,
            tags: [currentProjectTab]
        )
        captures.insert(item, at: 0)
        state = .completed(title: item.title)
        sync()
        return item
    }

    /// Save a typed note. Same events, same project tag, same sync as a spoken one.
    ///
    /// Returns nothing on purpose. `CaptureStore` is the sole owner of `captures`
    /// and `state`; handing the caller an item as well would give the UI a second
    /// way to learn one outcome, and two authorities drift.
    public func saveTypedNote(_ text: String) throws {
        guard !captureInFlight else { throw CaptureTextError.captureInFlight }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureTextError.empty }
        try saveCapturedText(trimmed, audioURL: nil)
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
            appendTargetNoteID = nil
            state = .error("No audio file recorded.")
            throw RecorderError.recordingFailed("No audio file recorded.")
        }

        state = .transcribing(audioURL: audioURL)
        partialTranscript = "Transcribing audio..."

        // Transcription is the ONLY failure the empty-audio fallback below is for.
        // It used to share one `catch` with persistence, so a failed shard or log
        // write was treated as a failed transcription and produced a SECOND, empty
        // note on top of the one that had just failed to save.
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(audioURL: audioURL, locale: effectiveTranscriptionLocale)
        } catch {
            let targetID = appendTargetNoteID
            appendTargetNoteID = nil

            if targetID == nil {
                // If a new capture's transcription fails, still create the note
                // with an empty transcript so the audio survives on disk and is
                // reachable and playable from the list under its fallback title.
                try? saveCapturedText("", audioURL: audioURL)
            }

            state = .error("Transcription failed: \(error.localizedDescription) (audio saved at \(audioURL.lastPathComponent))")
            throw error
        }

        partialTranscript = transcript

        // A voice append is a different contract: it appends to an existing note
        // and creates no capture item. Deliberately NOT part of `saveCapturedText`.
        if let targetNoteID = appendTargetNoteID {
            appendTargetNoteID = nil
            do {
                try appendToCapture(noteID: targetNoteID, text: transcript)
            } catch {
                state = .error("Could not append to the note: \(error.localizedDescription) (audio saved at \(audioURL.lastPathComponent))")
                throw error
            }
            state = .completed(title: "Appended to note")
            return "Appended to note"
        }

        do {
            return try saveCapturedText(transcript, audioURL: audioURL).title
        } catch {
            // A persistence failure, not a transcription one. Do NOT write a
            // second note: part of the first batch may already have landed, and
            // the log is append-only so there is nothing to roll back.
            state = .error("Audio saved as \(audioURL.lastPathComponent), but the note could not be written: \(error.localizedDescription)")
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
