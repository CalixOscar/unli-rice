import AppKit
import Foundation
import UnliRiceCore

enum StudioScope: Equatable { case project, all }
struct StudioGateKey: Equatable { let sleeveID: String?; let refresh: Int }

enum StudioGardenState: Equatable {
    case loading
    case loaded
    case failed(String)
}

extension AppStore {
    var studioFrontSleeve: GardenCrate.Sleeve? {
        guard studioSleeves.indices.contains(studioFrontIndex) else { return nil }
        return studioSleeves[studioFrontIndex]
    }

    func refreshStudioGarden() async {
        studioGardenState = .loading
        _ = runShardImportIfNeeded()
        let roots = scanRoots
        let corpusFolder = dataURL.deletingLastPathComponent()
        let service = service
        let identity = DeviceIdentity.current(inDirectory: corpusFolder)
        let exportFolder = nativeSyncMode == .folder ? exportFolderURL : nil

        do {
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let corpusAccess = corpusFolder.startAccessingSecurityScopedResource()
                defer { if corpusAccess { corpusFolder.stopAccessingSecurityScopedResource() } }
                let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
                defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
                return try NativeOverviewGatherer.gather(roots: roots, service: service, corpusFolder: corpusFolder, identity: identity)
            }
            let result = try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            let report = result.report, overview = result.overview, ids = result.receivedCaptureIDs
            var failures: [String] = []
            let corpusAccess = corpusFolder.startAccessingSecurityScopedResource()
            do { try overview.write(toFolder: corpusFolder) } catch { failures.append("local overview: \(error.localizedDescription)") }
            if corpusAccess { corpusFolder.stopAccessingSecurityScopedResource() }
            if let exportFolder {
                let scoped = exportFolder.startAccessingSecurityScopedResource()
                do { try overview.write(toFolder: exportFolder) } catch { failures.append("shared overview: \(error.localizedDescription)") }
                do {
                    try CaptureReceiptFile(deviceLabel: identity.label, receivedNoteIDs: ids).write(toFolder: exportFolder, deviceID: identity.id)
                } catch { failures.append("capture receipt: \(error.localizedDescription)") }
                if scoped { exportFolder.stopAccessingSecurityScopedResource() }
            }
            if !failures.isEmpty { statusMessage = "Studio sync needs retry: " + failures.joined(separator: "; ") }
            studioSleeves = GardenCrate.sleeves(from: report)
            studioFrontIndex = min(studioFrontIndex, max(studioSleeves.count - 1, 0))
            studioGardenState = .loaded
            studioRefreshCount &+= 1
            await loadStudioIcons()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            studioGardenState = .failed(error.localizedDescription)
        }
    }

    func loadStudioIcons() async {
        let projects = studioSleeves.compactMap { sleeve in
            sleeve.folderURL.map { (sleeve.id, $0) }
        }
        let roots = scanRoots
        let worker = Task.detached(priority: .utility) {
            let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
            var icons: [String: Data] = [:]
            for (id, folder) in projects {
                guard !Task.isCancelled else { break }
                if let url = ProjectIcon.find(in: folder),
                   (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 <= 5_000_000 }) == true,
                   let data = try? Data(contentsOf: url), data.count <= 5_000_000 {
                    icons[id] = data
                }
            }
            return icons
        }
        let data = await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: { worker.cancel() })
        guard !Task.isCancelled else { return }
        var icons: [String: NSImage] = [:]
        for (id, imageData) in data {
            if let image = NSImage(data: imageData), image.isValid { icons[id] = image }
        }
        studioIcons = icons
    }

    func refreshStudioGate() async {
        guard let folder = studioFrontSleeve?.folderURL else {
            studioFrontGate = nil
            return
        }
        let roots = scanRoots
        let result = await Task.detached(priority: .userInitiated) {
            let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
            return BuildGate.current(folder: folder)
        }.value
        guard !Task.isCancelled else { return }
        studioFrontGate = result
    }
}
