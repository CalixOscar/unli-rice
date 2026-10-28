import Foundation

public enum WidgetCorpus {
    public enum Unreadable: Error, Equatable {
        case settingsUnreadable
        case folderFailed
        case noGroupContainer
        case logMissing
        case logUnreadable
    }

    /// Resolves exactly as `unlirice-mcp` does, then REFUSES every fallback:
    /// `.defaultAfterFolderFailed` → .folderFailed; settings file present but
    /// undecodable → .settingsUnreadable; no App Group container → .noGroupContainer
    /// (never Application Support). Returns the log URL and a stable corpus identity
    /// (the resolved folder path) for B4.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        containerURL: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.calmdownoscar.unlirice"),
        settingsURL: URL? = nil,
        resolveBookmark: (Data) -> URL? = CorpusLocation.resolveSecurityScopedBookmark,
        startAccess: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
    ) -> Result<(log: URL, corpusID: String), Unreadable> {
        if let override = environment["UNLIRICE_DATA_PATH"], !override.isEmpty {
            let logURL = URL(fileURLWithPath: override)
            guard FileManager.default.fileExists(atPath: logURL.path) else {
                return .failure(.logMissing)
            }
            return .success((log: logURL, corpusID: logURL.deletingLastPathComponent().path))
        }

        let effectiveSettingsURL: URL
        if let settingsURL = settingsURL {
            effectiveSettingsURL = settingsURL
        } else if let envSettings = environment["UNLIRICE_AGENT_SETTINGS"], !envSettings.isEmpty {
            effectiveSettingsURL = URL(fileURLWithPath: envSettings)
        } else {
            guard let container = containerURL else {
                return .failure(.noGroupContainer)
            }
            effectiveSettingsURL = container.appendingPathComponent(DataLocation.directoryName, isDirectory: true).appendingPathComponent("agent.json")
        }

        let settings: AgentSettings
        do {
            settings = try AgentSettings.loadStrict(from: effectiveSettingsURL) ?? AgentSettings()
        } catch {
            return .failure(.settingsUnreadable)
        }

        guard let container = containerURL else {
            return .failure(.noGroupContainer)
        }

        let defaultFolder = container.appendingPathComponent(DataLocation.directoryName, isDirectory: true)
        let defaultLogURL = defaultFolder.appendingPathComponent("events.jsonl")

        let corpus = CorpusLocation.resolve(
            environment: environment,
            folderBookmark: settings.dataFolderBookmark,
            folderPath: settings.dataFolderPath,
            isSandboxed: true,
            defaultURL: defaultLogURL,
            resolveBookmark: resolveBookmark,
            startAccess: startAccess
        )

        switch corpus.source {
        case .defaultAfterFolderFailed:
            return .failure(.folderFailed)
        case .chosenFolder(let folder):
            let logURL = corpus.url
            guard FileManager.default.fileExists(atPath: logURL.path) else {
                return .failure(.logMissing)
            }
            return .success((log: logURL, corpusID: folder.path))
        case .defaultLocation:
            let logURL = corpus.url
            guard FileManager.default.fileExists(atPath: logURL.path) else {
                return .failure(.logMissing)
            }
            return .success((log: logURL, corpusID: defaultFolder.path))
        case .environmentOverride:
            let logURL = corpus.url
            guard FileManager.default.fileExists(atPath: logURL.path) else {
                return .failure(.logMissing)
            }
            return .success((log: logURL, corpusID: logURL.deletingLastPathComponent().path))
        }
    }
}
