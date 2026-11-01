import AppKit
import Foundation
import UnliRiceCore

final class NativeSyncGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func invalidate() { lock.lock(); value &+= 1; lock.unlock() }
    func snapshot() -> Int { lock.lock(); defer { lock.unlock() }; return value }
    func valid(_ generation: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return value == generation }
}

extension AppStore {
    func nativeStatus(_ message: String) -> String {
        [projectionDiagnostics.summary, message].compactMap { $0 }.joined(separator: " ")
    }
    func loadNativeSyncPreferences() {
        do {
            nativeSyncMode = try NativeSyncPreferences.load(besideEventLog: dataURL, legacyFolderChosen: exportFolderURL != nil).mode
            nativeSyncStatus = nativeStatus(nativeSyncMode == .iCloud ? "Waiting to sync" : "On this device")
        } catch {
            nativeSyncMode = .privateDevice
            nativeSyncStatus = nativeStatus("Sync paused: \(error.localizedDescription)")
        }
    }

    func invalidateNativeSync() {
        nativeGeneration.invalidate()
        nativeTask?.cancel()
        nativeTask = nil
        nativeDiscovery.stop()
        nativeWatchedRootURL = nil
        nativePendingConsent = false
    }

    func enableNativeSync() {
        do {
            try NativeSyncPreferences(mode: .iCloud).save(besideEventLog: dataURL)
            invalidateNativeSync()
            nativeSyncMode = .iCloud
            nativePendingConsent = true
            startNativeSync(explicitConsent: true)
        } catch { nativeSyncStatus = nativeStatus("Sync paused: \(error.localizedDescription)") }
    }

    func stopNativeSync() {
        do {
            try NativeSyncPreferences(mode: .privateDevice).save(besideEventLog: dataURL)
            invalidateNativeSync()
            nativeSyncMode = .privateDevice
            nativeSyncStatus = nativeStatus("On this device")
        } catch { nativeSyncStatus = nativeStatus("Sync paused: \(error.localizedDescription)") }
    }

    func useSharedFolderSync() {
        guard exportFolderURL != nil else { return }
        do {
            try NativeSyncPreferences(mode: .folder).save(besideEventLog: dataURL)
            invalidateNativeSync()
            nativeSyncMode = .folder
            nativeSyncStatus = nativeStatus("Shared folder sync is on")
            runShardImportIfNeeded()
        } catch { nativeSyncStatus = nativeStatus("Sync paused: \(error.localizedDescription)") }
    }

    func startNativeSync(explicitConsent: Bool = false) {
        guard nativeSyncMode == .iCloud, nativeTask == nil else { return }
        let allowCreate = explicitConsent && nativePendingConsent
        nativePendingConsent = false
        let generation = nativeGeneration.snapshot(), token = nativeGeneration, workLock = nativeWorkLock
        let log = dataURL, roots = scanRoots, service = service
        let identity = DeviceIdentity.current(inDirectory: log.deletingLastPathComponent())
        let discovered = nativeDiscovery.urls
        nativeSyncStatus = nativeStatus("Syncing…")
        nativeTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) { () -> (Result<(NativeCloudSession, NativeCloudTransport.Result, ProjectionDiagnostics), Error>, Int) in
                var imported = 0
                do {
                    workLock.lock()
                    defer { workLock.unlock() }
                    let valid = { token.valid(generation) }
                    guard valid() else { throw CancellationError() }
                    let folder = log.deletingLastPathComponent()
                    let scoped = folder.startAccessingSecurityScopedResource()
                    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                    let opened = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
                    defer { for (root, access) in opened where access { root.stopAccessingSecurityScopedResource() } }
                    let session = try NativeCloudSession.resolve(eventLogURL: log, allowCreate: allowCreate, isValid: valid)
                    let current = { valid() && session.isCurrentAccount() }
                    var sync = try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: session.rootURL, binding: session.binding, deviceID: identity.id, accountIsCurrent: current, discoveredURLs: discovered)
                    imported += sync.eventsImported
                    for _ in 0..<19 where sync.hasMoreWork {
                        sync = try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: session.rootURL, binding: session.binding, deviceID: identity.id, accountIsCurrent: current, discoveredURLs: discovered)
                        imported += sync.eventsImported
                    }
                    guard current() else { throw CancellationError() }
                    if imported > 0 { service.rebuild() }
                    let snapshot = try service.projectionSnapshot(includeArchived: true)
                    let ids = snapshot.notes.filter { CaptureContext.isCapture($0) }.sorted { $0.updatedAt > $1.updatedAt }.prefix(2000).map(\.id)
                    try NativeCloudTransport.publishReceipt(CaptureReceiptFile(deviceLabel: identity.label, receivedNoteIDs: ids), rootURL: session.rootURL, deviceID: identity.id, accountIsCurrent: current)
                    let gathered = try NativeOverviewGatherer.gather(roots: roots, service: service, corpusFolder: folder, identity: identity)
                    guard current() else { throw CancellationError() }
                    if !gathered.report.projects.isEmpty {
                        try NativeCloudTransport.publishOverview(gathered.overview, rootURL: session.rootURL, deviceID: identity.id, accountIsCurrent: current)
                    }
                    guard current() else { throw CancellationError() }
                    try gathered.overview.write(toFolder: folder)
                    return (.success((session, sync, snapshot.diagnostics)), imported)
                } catch {
                    if imported > 0 { service.rebuild() }
                    return (.failure(error), imported)
                }
            }.value
            guard let self, token.valid(generation), self.dataURL == log, self.nativeSyncMode == .iCloud else { return }
            self.nativeTask = nil
            switch outcome.0 {
            case .success(let (session, sync, diagnostics)):
                guard session.isCurrentAccount() else {
                    self.invalidateNativeSync()
                    self.nativeSyncStatus = self.nativeStatus("iCloud account changed; sync paused.")
                    return
                }
                if outcome.1 > 0 { self.reload() }
                self.nativeSyncStatus = diagnostics.summary ?? (sync.issues.isEmpty ? (sync.waitingForDownloads ? "Waiting for iCloud downloads" : "iCloud sync is on") : sync.issues.joined(separator: " "))
                if self.nativeWatchedRootURL != session.rootURL {
                    self.nativeWatchedRootURL = session.rootURL
                    self.nativeDiscovery.start(rootURL: session.rootURL) { [weak self] in self?.startNativeSync() }
                }
                if sync.hasMoreWork {
                    self.startNativeSync()
                }
            case .failure(let error):
                if outcome.1 > 0 { self.reload() }
                self.nativeSyncStatus = [self.projectionDiagnostics.summary, "Sync paused: \(error.localizedDescription)"].compactMap { $0 }.joined(separator: " ")
            }
        }
    }
}
