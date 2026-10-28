import Foundation
import UnliRiceCore

/// The optional features that sit beside the app's three jobs. Each one is a
/// switch on its *door* (sidebar row, menu item, button); turning one off never
/// deletes code or data. The two background extras (bulk import, duplicate
/// detection) are not cases here: they live in `AgentSettings`, because the
/// background agent has to read them.
enum Extra: String, CaseIterable, Identifiable {
    case projects, todo, map, yearSoFar, profiles, extraExports, capturePromo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Projects"
        case .todo: return "To do"
        case .map: return "Map"
        case .yearSoFar: return "Your year so far"
        case .profiles: return "Separate memories"
        case .extraExports: return "PDF and ZIP export"
        case .capturePromo: return "iPhone Capture"
        }
    }

    var detail: String {
        switch self {
        case .projects: return "Git status and next steps for the folders in Setup › Folders."
        case .todo: return "A list built from your repos, project notes, and notes your AI tagged."
        case .map: return "A graph of how your notes link to each other."
        case .yearSoFar: return "A look back over a month or a year of your notes."
        case .profiles: return "Keep more than one memory, each with its own notes."
        case .extraExports: return "Adds PDF and ZIP to File › Export."
        case .capturePromo: return "Shows the card for the free iPhone app in the sidebar."
        }
    }
}

extension AppStore {
    func isOn(_ extra: Extra) -> Bool {
        enabledExtras.contains(extra)
    }

    /// Updates the set and writes it out. Never navigates: a switch controls
    /// the door, not where the user currently is.
    func setExtra(_ extra: Extra, on: Bool) {
        if on {
            enabledExtras.insert(extra)
        } else {
            enabledExtras.remove(extra)
        }
        saveExtras()
    }

    /// Reads the saved set. When the key is absent (first launch of the version
    /// that has extras), an existing install keeps Projects and To do on so
    /// nothing is taken away; a new install starts with everything off. The
    /// result is written at once and never recomputed. A saved empty array is
    /// respected.
    func loadExtras() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.enabledExtrasKey) {
            enabledExtras = Set(saved.compactMap(Extra.init(rawValue:)))
            return
        }
        let logSize = (try? FileManager.default.attributesOfItem(atPath: dataURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let hasScanRoots = !(UserDefaults.standard.stringArray(forKey: Self.scanRootsKey) ?? []).isEmpty
        enabledExtras = (logSize > 0 || hasScanRoots) ? [.projects, .todo] : []
        saveExtras()
    }

    private func saveExtras() {
        UserDefaults.standard.set(
            Extra.allCases.filter { enabledExtras.contains($0) }.map(\.rawValue),
            forKey: Self.enabledExtrasKey
        )
    }
}
