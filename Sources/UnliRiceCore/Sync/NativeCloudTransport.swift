import Foundation

public enum NativeCloudTransport {
    public struct Result: Sendable {
        public let eventsImported: Int
        public let eventsPublished: Int
        public let waitingForDownloads: Bool
        /// Whether another immediate pass can advance local or ready cloud work.
        public let hasMoreWork: Bool
        public let issues: [String]
    }
    public struct OverviewResult: Sendable {
        public let overview: StudioOverviewFile?
        public let waitingForDownloads: Bool
        public let issues: [String]
    }
    public enum TransportError: Error, LocalizedError {
        case accountChanged, invalidState, unsupportedState(Int), sourceMissing, sourceShrunk, invalidBatch, unsafePath, overviewDownloading
        public var errorDescription: String? {
            switch self {
            case .accountChanged: return "The iCloud account changed; sync is paused."
            case .invalidState: return "Native sync state is unreadable."
            case .unsupportedState(let v): return "Unsupported native sync state version \(v)."
            case .sourceMissing: return "The local event log is missing."
            case .sourceShrunk: return "The local event log became shorter; sync is paused."
            case .invalidBatch: return "An event batch is invalid or too large."
            case .unsafePath: return "A cloud item is outside the native sync folder."
            case .overviewDownloading: return "Waiting for the previous iCloud project overview to download."
            }
        }
    }
    private struct State: Codable {
        var version = 1
        var exportedOffset: UInt64 = 0
        var imported: Set<String> = []
    }
    private static let maxBytes = 2 * 1024 * 1024
    private static let maxLine = EventStore.maxNativeLineBytes
    private static func stateURL(_ log: URL, _ binding: NativeCloudBinding) -> URL {
        log.deletingLastPathComponent().appendingPathComponent("native-cloud-state-\(binding.bindingID.uuidString).json")
    }
    private static func loadState(_ url: URL) throws -> State {
        guard FileManager.default.fileExists(atPath: url.path) else { return State() }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int else { throw TransportError.invalidState }
        guard version == 1 else { throw TransportError.unsupportedState(version) }
        guard let state = try? JSONDecoder().decode(State.self, from: data) else { throw TransportError.invalidState }
        return state
    }
    private static func safeID(_ value: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw TransportError.unsafePath }
        return value
    }
    private static func requireAccount(_ current: () -> Bool) throws { guard current() else { throw TransportError.accountChanged } }
    private static func boundedData(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw TransportError.invalidBatch }
        return data
    }
    private struct Record {
        let event: Event
        let raw: Data
        let endOffset: UInt64
    }
    private static func records(_ data: Data) throws -> [Record] {
        guard data.isEmpty || data.last == 10 else { throw TransportError.invalidBatch }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var offset: UInt64 = 0, result: [Record] = []
        for line in data.split(separator: 10, omittingEmptySubsequences: false).dropLast() {
            guard !line.isEmpty, line.count <= maxLine,
                  let event = try? decoder.decode(Event.self, from: Data(line)),
                  Set(event.causalParents ?? []).count <= 1024 else { throw TransportError.invalidBatch }
            if event.kind == .causalOrder && (event.relatedEventId == nil || event.causalParents == nil) { throw TransportError.invalidBatch }
            offset += UInt64(line.count + 1)
            result.append(Record(event: event, raw: Data(line), endOffset: offset))
        }
        return result
    }
    private static func validate(_ data: Data) throws -> [Record] {
        guard !data.isEmpty, data.count <= maxBytes else { throw TransportError.invalidBatch }
        let batch = try records(data)
        guard !batch.isEmpty, batch.count <= 500 else { throw TransportError.invalidBatch }
        let declarations = batch.filter { $0.event.kind == .causalOrder }
        for record in batch where record.event.kind != .causalOrder && record.event.causalParents == nil {
            guard declarations.contains(where: { $0.event.relatedEventId == record.event.id && $0.event.noteId == record.event.noteId }) else { throw TransportError.invalidBatch }
        }
        for declaration in declarations {
            if let target = batch.first(where: { $0.event.id == declaration.event.relatedEventId }), target.event.noteId != declaration.event.noteId { throw TransportError.invalidBatch }
        }
        return batch
    }
    private static func exportWindow(_ data: Data, offset: UInt64) throws -> (Data, UInt64, Int, Bool) {
        guard offset <= UInt64(data.count) else { throw TransportError.sourceShrunk }
        let all = try records(data)
        guard offset == 0 || all.contains(where: { $0.endOffset == offset }) else { throw TransportError.invalidState }
        let originals = all.filter { $0.endOffset > offset }
        var declarations: [UUID: [Record]] = [:]
        for record in all where record.event.kind == .causalOrder {
            declarations[record.event.relatedEventId!, default: []].append(record)
        }
        var selected: [Record] = [], ids = Set<UUID>(), bytes = 0, advanced = offset
        for original in originals {
            var additions = [original]
            if original.event.kind != .causalOrder && original.event.causalParents == nil {
                let matching = declarations[original.event.id, default: []]
                guard !matching.isEmpty, matching.allSatisfy({ $0.event.noteId == original.event.noteId }) else { throw TransportError.invalidBatch }
                additions.append(contentsOf: matching)
            }
            var newIDs = ids
            let unique = additions.filter { newIDs.insert($0.event.id).inserted }
            let length = unique.reduce(0) { $0 + $1.raw.count + 1 }
            if selected.count + unique.count > 500 || bytes + length > maxBytes {
                guard advanced != offset else { throw TransportError.invalidBatch }
                break
            }
            selected.append(contentsOf: unique); ids = newIDs; bytes += length; advanced = original.endOffset
        }
        var output = Data()
        for record in selected { output.append(record.raw); output.append(10) }
        if !output.isEmpty { _ = try validate(output) }
        return (output, advanced, selected.count, advanced < UInt64(data.count))
    }
    private static func inside(_ url: URL, root: URL) -> Bool {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(base + "/") && url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == base
    }
    private static func candidates(root: URL, discovered: [URL], prefix: String, suffix: String, excluding: Set<String> = []) throws -> ([URL], Bool) {
        let listed = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var byName: [String: URL] = [:]
        for url in listed + discovered {
            guard inside(url, root: root) else { if discovered.contains(url) { throw TransportError.unsafePath }; continue }
            let name = url.lastPathComponent
            let canonical = name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(7)) : name
            if canonical.hasPrefix(prefix) && canonical.hasSuffix(suffix) && !excluding.contains(canonical) { byName[name] = url }
        }
        let sorted = byName.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return (Array(sorted.prefix(1000)), sorted.count > 1000)
    }
    private static func ready(_ url: URL) throws -> Bool {
        if url.pathExtension == "icloud" { try? FileManager.default.startDownloadingUbiquitousItem(at: url); return false }
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: url); return false
        }
        return true
    }
    private static func coordinatedRead<T>(_ url: URL, current: () -> Bool, body: (URL) throws -> T) throws -> T {
        try requireAccount(current)
        var failure: NSError?; var result: Swift.Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { location in
            result = Swift.Result { try requireAccount(current); return try body(location) }
        }
        if let failure { throw failure }
        guard let result else { throw TransportError.invalidBatch }
        return try result.get()
    }
    private static func coordinatedWrite(_ url: URL, current: () -> Bool, body: (URL) throws -> Void) throws {
        try requireAccount(current)
        var failure: NSError?; var result: Swift.Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &failure) { location in
            result = Swift.Result { try requireAccount(current); try body(location) }
        }
        if let failure { throw failure }
        guard let result else { throw TransportError.invalidBatch }
        try result.get()
    }
    public static func synchronize(eventLogURL: URL, rootURL: URL, binding: NativeCloudBinding, deviceID: String,
                                   accountIsCurrent: () -> Bool, discoveredURLs: [URL] = []) throws -> Result {
        try requireAccount(accountIsCurrent)
        let id = try safeID(deviceID)
        let stateFile = stateURL(eventLogURL, binding)
        let initial = try CaptureSyncBridge.withLock(eventLogURL: eventLogURL) { try loadState(stateFile) }
        guard FileManager.default.fileExists(atPath: eventLogURL.path) else { throw TransportError.sourceMissing }
        let source = try EventStore(readingExisting: eventLogURL).nativeCausalSnapshot()
        let snapshot = try exportWindow(source, offset: initial.exportedOffset)
        let (urls, truncated) = try candidates(root: rootURL, discovered: discoveredURLs, prefix: "events-", suffix: ".jsonl", excluding: initial.imported)
        var staged: [(String, [Record])] = [], waiting = truncated, stagedBytes = 0
        var moreCloud = truncated
        var issues: [String] = truncated ? ["More cloud batches remain to be checked."] : []
        for url in urls {
            try requireAccount(accountIsCurrent)
            guard try ready(url) else { waiting = true; continue }
            if staged.count >= 32 { moreCloud = true; issues.append("More cloud batches remain to be checked."); break }
            let bytes = try coordinatedRead(url, current: accountIsCurrent) { try boundedData($0) }
            if stagedBytes + bytes.count > 16 * 1024 * 1024 { moreCloud = true; issues.append("More cloud batches remain to be checked."); break }
            let entries = try validate(bytes)
            stagedBytes += bytes.count
            staged.append((url.lastPathComponent, entries))
        }
        if !snapshot.0.isEmpty {
            let target = rootURL.appendingPathComponent("events-\(id)-\(UUID().uuidString).jsonl")
            try coordinatedWrite(target, current: accountIsCurrent) { try snapshot.0.write(to: $0, options: .atomic) }
        }
        try requireAccount(accountIsCurrent)
        let imported = try CaptureSyncBridge.withLock(eventLogURL: eventLogURL) {
            try requireAccount(accountIsCurrent)
            var state = try loadState(stateFile)
            guard FileManager.default.fileExists(atPath: eventLogURL.path) else { throw TransportError.sourceMissing }
            let attributes = try FileManager.default.attributesOfItem(atPath: eventLogURL.path)
            guard let size = (attributes[.size] as? NSNumber)?.uint64Value, size >= max(state.exportedOffset, snapshot.1) else { throw TransportError.sourceShrunk }
            let store = try EventStore(readingExisting: eventLogURL)
            var seen = Set(try store.readAll().map(\.id)), pending: [Data] = [], processed: [String] = []
            for (name, entries) in staged where !state.imported.contains(name) {
                for record in entries where seen.insert(record.event.id).inserted { pending.append(record.raw) }
                processed.append(name)
            }
            try store.appendRawBatch(pending)
            state.imported.formUnion(processed)
            let count = pending.count
            state.exportedOffset = max(state.exportedOffset, snapshot.1)
            try JSONEncoder().encode(state).write(to: stateFile, options: .atomic)
            return (count, processed.count)
        }
        if snapshot.3 { issues.append("More local events remain to be published.") }
        let hasMoreWork = snapshot.3 || imported.0 > 0 || (moreCloud && imported.1 > 0)
        return Result(eventsImported: imported.0, eventsPublished: snapshot.2, waitingForDownloads: waiting, hasMoreWork: hasMoreWork, issues: issues)
    }
    public static func publishOverview(_ overview: StudioOverviewFile, rootURL: URL, deviceID: String,
                                       accountIsCurrent: () -> Bool) throws {
        let id = try safeID(deviceID)
        guard overview.version == StudioOverviewFile.currentVersion else { throw StudioOverviewFile.ReadError.unsupportedVersion(overview.version) }
        guard overview.projects.count <= 500 else { throw StudioOverviewFile.ReadError.tooManyProjects }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard try encoder.encode(overview).count <= maxBytes else { throw StudioOverviewFile.ReadError.oversized }
        try requireAccount(accountIsCurrent)
        let file = "studio-overview-\(id).json", url = rootURL.appendingPathComponent(file)
        let placeholder = rootURL.appendingPathComponent(".\(file).icloud")
        if FileManager.default.fileExists(atPath: url.path) {
            guard try ready(url) else { throw TransportError.overviewDownloading }
        } else if FileManager.default.fileExists(atPath: placeholder.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw TransportError.overviewDownloading
        }
        try coordinatedWrite(url, current: accountIsCurrent) { target in
            if FileManager.default.fileExists(atPath: target.path) {
                guard try ready(target) else { throw TransportError.overviewDownloading }
                do {
                    let old = try StudioOverviewFile.read(fromFolder: target.deletingLastPathComponent(), filename: target.lastPathComponent)
                    if old.generatedAt >= overview.generatedAt { return }
                } catch StudioOverviewFile.ReadError.unsupportedVersion(let version) {
                    throw StudioOverviewFile.ReadError.unsupportedVersion(version)
                } catch StudioOverviewFile.ReadError.unreadable {
                    // Current corrupt data may be replaced by a validated overview.
                } catch StudioOverviewFile.ReadError.oversized {
                } catch StudioOverviewFile.ReadError.tooManyProjects {
                }
            }
            try overview.write(toFolder: target.deletingLastPathComponent(), filename: target.lastPathComponent)
        }
    }
    public static func latestOverview(rootURL: URL, accountIsCurrent: () -> Bool, discoveredURLs: [URL] = []) throws -> OverviewResult {
        try requireAccount(accountIsCurrent)
        let (urls, truncated) = try candidates(root: rootURL, discovered: discoveredURLs, prefix: "studio-overview-", suffix: ".json")
        var waiting = truncated, issues = truncated ? ["More studio overviews remain to be checked."] : [String]()
        var newest: StudioOverviewFile?
        for url in urls {
            try requireAccount(accountIsCurrent)
            do {
                guard try ready(url) else { waiting = true; continue }
                let value = try coordinatedRead(url, current: accountIsCurrent) { try StudioOverviewFile.read(fromFolder: $0.deletingLastPathComponent(), filename: $0.lastPathComponent) }
                if newest == nil || value.generatedAt > newest!.generatedAt { newest = value }
            } catch TransportError.accountChanged { throw TransportError.accountChanged }
            catch { issues.append("A studio overview could not be read.") }
        }
        return OverviewResult(overview: newest, waitingForDownloads: waiting, issues: issues)
    }
    public static func publishReceipt(_ receipt: CaptureReceiptFile, rootURL: URL, deviceID: String,
                                      accountIsCurrent: () -> Bool) throws {
        let id = try safeID(deviceID)
        let url = rootURL.appendingPathComponent(CaptureReceiptFile.filename(deviceID: id))
        try coordinatedWrite(url, current: accountIsCurrent) { target in
            try receipt.write(toFolder: target.deletingLastPathComponent(), deviceID: id)
        }
    }
    public static func receivedCaptureIDs(rootURL: URL, accountIsCurrent: () -> Bool, discoveredURLs: [URL] = []) throws -> Set<UUID> {
        try requireAccount(accountIsCurrent)
        let (urls, truncated) = try candidates(root: rootURL, discovered: discoveredURLs, prefix: "capture-receipt-", suffix: ".json")
        guard !truncated else { throw TransportError.invalidBatch }
        var ids = Set<UUID>()
        for url in urls {
            guard try ready(url) else { continue }
            let receipt: CaptureReceiptFile = try coordinatedRead(url, current: accountIsCurrent) { location in
                let data = try boundedData(location)
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                guard let value = try? decoder.decode(CaptureReceiptFile.self, from: data), value.version == 1,
                      value.receivedNoteIDs.count <= 2000 else { throw TransportError.invalidBatch }
                return value
            }
            ids.formUnion(receipt.receivedNoteIDs)
        }
        return ids
    }
}
