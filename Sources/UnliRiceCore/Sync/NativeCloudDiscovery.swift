import Foundation

@MainActor public final class NativeCloudDiscovery: NSObject {
    public private(set) var urls: [URL] = []
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var change: (() -> Void)?
    private var downloadTask: Task<Void, Never>?
    public func start(rootURL: URL, onChange: @escaping () -> Void) {
        stop()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, rootURL.standardizedFileURL.path + "/")
        self.query = query
        change = onChange
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.gather() }
            })
        }
        query.start()
    }
    public func stop() {
        downloadTask?.cancel(); downloadTask = nil
        query?.stop(); query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []; urls = []; change = nil
    }
    /// A bounded snapshot for command-line callers that do not retain a watcher.
    public static func gatherOnce(rootURL: URL, timeout: TimeInterval = 0.5) -> [URL] {
        let watcher = NativeCloudDiscovery()
        watcher.start(rootURL: rootURL, onChange: {})
        let deadline = Date().addingTimeInterval(min(max(timeout, 0), 1))
        while Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
        let query = watcher.query
        query?.disableUpdates()
        let result = query?.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL } ?? []
        query?.enableUpdates()
        watcher.stop()
        return result
    }
    private func gather() {
        guard let query else { return }
        query.disableUpdates(); defer { query.enableUpdates() }
        urls = query.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL }
        downloadTask?.cancel()
        let pending = urls
        downloadTask = Task.detached(priority: .utility) {
            for url in pending {
                guard !Task.isCancelled else { return }
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        change?()
    }
}
