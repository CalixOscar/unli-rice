import AppKit
import Foundation
import UnliRiceCore

/// Which screen of Get Started is showing.
enum SetupStage: Equatable {
    /// Autopilot toggle, and the choice between connecting a tool and pointing
    /// at an existing folder.
    case start
    /// The MCP picker. Cannot be left without at least one usable target.
    case chooseTargets
    /// Per-target outcomes: written, already correct, or paste-this.
    case results
}

/// What happened when Autopilot tried to connect one tool.
struct ConnectionResult: Identifiable, Equatable {
    enum Status: Equatable {
        case written(backup: URL?)
        case alreadyCorrect
        /// Either the format isn't edited automatically (Codex TOML), or the
        /// write was refused. `reason` is shown verbatim next to the block.
        case pasteRequired(reason: String)
    }

    let target: MCPTarget
    let status: Status
    /// Always present, including on success — someone may want to check what
    /// landed, or repeat it on another machine.
    let snippet: String
    let configPath: String

    var id: String { target.id }
}

/// Get Started, rebuilt around connecting an MCP client.
///
/// The previous design interviewed the user with the local model and handed
/// them a prompt to paste elsewhere. It was cut after a real run: Qwen ended the
/// interview after one answer, and the artifact came out with no stack, no tool
/// and no conventions in it. Nothing in this file calls a model. Every step is
/// deterministic, which is also why all of it is testable.
///
/// The one genuinely delicate thing here is writing config files this app didn't
/// create — see `MCPConfigWriter` for the three rules that make that acceptable.
extension AppStore {
    /// Catalog plus anything the user added by hand.
    var availableTargets: [MCPTarget] { MCPTarget.builtIn + customTargets }

    func target(id: String) -> MCPTarget? {
        availableTargets.first { $0.id == id }
    }

    // MARK: - Selection

    func toggleTarget(_ target: MCPTarget) {
        if selectedTargetIDs.contains(target.id) {
            selectedTargetIDs.remove(target.id)
        } else {
            selectedTargetIDs.insert(target.id)
        }
    }

    /// A project-scoped target isn't usable until the user says which project.
    func isTargetReady(_ target: MCPTarget) -> Bool {
        guard selectedTargetIDs.contains(target.id) else { return false }
        return !target.requiresProjectFolder || targetProjectFolders[target.id] != nil
    }

    /// Gates the Connect button. The requirement that at least one tool is
    /// connected is the point of the screen — Unli Rice with nothing attached
    /// to it is exactly the state a new user is stuck in.
    var canConnect: Bool {
        let selected = availableTargets.filter { selectedTargetIDs.contains($0.id) }
        return !selected.isEmpty && selected.allSatisfy(isTargetReady)
    }

    func chooseProjectFolder(for target: MCPTarget) {
        let panel = NSOpenPanel()
        panel.title = "Choose the project folder for \(target.displayName)"
        panel.message = "\(target.displayName) keeps MCP servers per project. Pick the project you want these notes available in."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        targetProjectFolders[target.id] = folder
    }

    /// Adds a tool that isn't in the catalog. The user picks the config file
    /// itself — guessing a path for a tool whose format we haven't verified is
    /// how a config that silently never connects gets written.
    func addCustomTarget() {
        let panel = NSOpenPanel()
        panel.title = "Choose your tool's MCP config file"
        panel.message = "Pick the config file (.json or .toml). The name of its folder is used as the tool's name."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json, .init(filenameExtension: "toml")].compactMap { $0 }
        panel.prompt = "Use This File"
        guard panel.runModal() == .OK, let file = panel.url else { return }

        let target = MCPTarget.custom(name: file.lastPathComponent, fileURL: file)
        guard !availableTargets.contains(where: { $0.id == target.id }) else { return }
        customTargets.append(target)
        selectedTargetIDs.insert(target.id)
    }

    // MARK: - Connecting

    /// Writes what can be written, renders what can't, and — if Autopilot is on
    /// — leaves the house-rules note behind.
    func connectSelectedTargets() {
        let entry = MCPServerEntry.forPackage(
            at: Autopilot.detectedPackageRoot(), dataPathOverride: mcpDataPathOverride
        )

        connectionResults = availableTargets
            .filter { selectedTargetIDs.contains($0.id) }
            .map { result(for: $0, entry: entry) }

        if autopilotEnabled {
            writeHouseRulesNote()
        }
        markGetStartedComplete()
        setupStage = .results
    }

    private func result(for target: MCPTarget, entry: MCPServerEntry) -> ConnectionResult {
        let url = target.configURL(projectFolder: targetProjectFolders[target.id])
        let snippet = MCPConfigWriter.snippet(for: target.format, entry: entry)
        let path = url?.path ?? target.detail

        guard target.supportsAutomaticWrite, let url else {
            return ConnectionResult(
                target: target,
                status: .pasteRequired(
                    reason: MCPConfigWriter.WriteError.unsupportedFormat(target.format).description
                ),
                snippet: snippet,
                configPath: path
            )
        }

        do {
            switch try MCPConfigWriter.merge(entry: entry, intoJSONAt: url) {
            case .created:
                return ConnectionResult(target: target, status: .written(backup: nil), snippet: snippet, configPath: path)
            case .updated(_, let backup):
                return ConnectionResult(target: target, status: .written(backup: backup), snippet: snippet, configPath: path)
            case .unchanged:
                return ConnectionResult(target: target, status: .alreadyCorrect, snippet: snippet, configPath: path)
            }
        } catch {
            // A refused or failed write is a normal outcome, not an error
            // banner: the user still gets the exact block to paste, which is
            // what they'd have got from the old flow anyway.
            return ConnectionResult(
                target: target,
                status: .pasteRequired(reason: "\(error)"),
                snippet: snippet,
                configPath: path
            )
        }
    }

    /// The note that teaches a connected assistant the habit — read the notes at
    /// the start of a session, write them at the end. Skipped when Autopilot is
    /// off, for someone who'd rather set their own conventions.
    private func writeHouseRulesNote() {
        do {
            let title = Autopilot.noteTitle(existingTitles: (notes + archivedNotes).map(\.title))
            // `source: "unlirice"` — this is the app's own voice, the same as
            // the seeded guides. It isn't something the user wrote, and marking
            // it "human" would make the transaction log lie.
            let note = try service.createNote(
                title: title, body: Autopilot.noteBody, source: Onboarding.source
            )
            try service.tagNote(id: note.id, tag: Autopilot.noteTag, source: Onboarding.source)
            reload()
        } catch {
            errorMessage = "Couldn't write the how-to note: \(error)"
        }
    }

    // MARK: - Existing vault

    /// Points the app at a folder that already holds an `events.jsonl`. Still
    /// goes on to the MCP picker afterwards — an existing corpus that nothing
    /// is connected to has the same problem as an empty one.
    func chooseExistingVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose the folder holding your notes"
        panel.message = "Pick a folder containing events.jsonl — or an empty folder to start one there."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        guard switchDataFolder(to: folder) else { return }
        setupStage = .chooseTargets
    }

    // MARK: - Navigation

    func beginTargetSelection() {
        connectionResults = []
        setupStage = .chooseTargets
    }

    func restartSetup() {
        connectionResults = []
        selectedTargetIDs = []
        setupStage = .start
    }

    func copySnippet(_ snippet: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        statusMessage = "Config block copied."
    }

    /// Emitted into a generated config only when the user has *deliberately*
    /// pointed the app at a folder.
    ///
    /// Reading this off `dataURL` was a real bug: launching the app once with
    /// `UNLIRICE_DATA_PATH` set for a test baked that throwaway path into the
    /// config block. The persisted preference is the only signal that means
    /// "the user chose this", so it's the one used.
    private var mcpDataPathOverride: URL? {
        guard let folder = UserDefaults.standard.string(forKey: Self.dataFolderKey),
              !folder.isEmpty
        else { return nil }
        let url = DataLocation.eventLogURL(inFolder: URL(fileURLWithPath: folder, isDirectory: true))
        return url == DataLocation.defaultEventLogURL() ? nil : url
    }
}
