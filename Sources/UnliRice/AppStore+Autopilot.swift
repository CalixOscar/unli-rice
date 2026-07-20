import AppKit
import Foundation
import UnliRiceCore

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

    /// Connects exactly one tool, immediately.
    ///
    /// This is what the connector table calls, and it replaces the old
    /// tick-boxes-then-Connect-then-results wizard. Connecting Cursor and
    /// connecting Claude Desktop were never one decision that needed batching —
    /// they're two independent switches, and modelling them as a multi-select
    /// flow meant a user who wanted one tool still had to walk three screens and
    /// then find their way back out. Each row now owns its own outcome, kept in
    /// `connectionResults` and rendered in place under the row that produced it.
    func connect(_ target: MCPTarget) {
        // A project-scoped tool with no folder yet has one obvious next step;
        // asking for the folder *is* the connect action in that case, rather
        // than a disabled button and a note explaining why it's disabled.
        if target.requiresProjectFolder, targetProjectFolders[target.id] == nil {
            chooseProjectFolder(for: target)
            guard targetProjectFolders[target.id] != nil else { return }
        }

        let entry = MCPServerEntry.forPackage(
            at: Autopilot.detectedPackageRoot(), dataPathOverride: mcpDataPathOverride
        )
        let outcome = result(for: target, entry: entry)
        connectionResults.removeAll { $0.id == target.id }
        connectionResults.append(outcome)
        selectedTargetIDs.insert(target.id)

        // Connecting no longer writes the house-rules note as a side effect.
        // That was the Autopilot switch's whole job, and a switch is the wrong
        // control for a block of prompt text — see `AppStore.houseRulesText`.
        // The note is now saved by a visible button, next to the text it saves.
        markGetStartedComplete()

        switch outcome.status {
        case .written:
            statusMessage = "Connected \(target.displayName) — restart it to pick this up."
        case .alreadyCorrect:
            statusMessage = "\(target.displayName) was already connected."
        case .pasteRequired:
            statusMessage = "\(target.displayName) needs the config pasted in by hand."
        }
    }

    /// Read-only state for one row of the connector table.
    func presence(of target: MCPTarget) -> MCPConfigWriter.Presence {
        guard target.supportsAutomaticWrite else { return .absent }
        let entry = MCPServerEntry.forPackage(
            at: Autopilot.detectedPackageRoot(), dataPathOverride: mcpDataPathOverride
        )
        return MCPConfigWriter.presence(
            of: entry, inJSONAt: target.configURL(projectFolder: targetProjectFolders[target.id])
        )
    }

    func result(forTargetID id: String) -> ConnectionResult? {
        connectionResults.first { $0.id == id }
    }

    /// The paste block for a target, for the tools we don't write to.
    func snippet(for target: MCPTarget) -> String {
        MCPConfigWriter.snippet(
            for: target.format,
            entry: MCPServerEntry.forPackage(
                at: Autopilot.detectedPackageRoot(), dataPathOverride: mcpDataPathOverride
            )
        )
    }

    /// The house-rules note, if it's been saved. Drives the button's label —
    /// "Save to notes" and "Update the note" are different promises.
    var houseRulesNote: Note? {
        (notes + archivedNotes).first { $0.title.hasPrefix(Autopilot.noteTitleBase) }
    }

    /// Whether the saved note already says what the editor currently says.
    /// Guards the button, because on an append-only log "save" with no changes
    /// isn't a no-op — it's a second copy of the same text inside one note.
    var houseRulesAreSaved: Bool {
        guard let note = houseRulesNote else { return false }
        return note.body.contains(houseRulesText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func resetHouseRules() {
        houseRulesText = Autopilot.noteBody
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
    /// Saves the house rules the user is looking at.
    ///
    /// Two paths, because titles are permanent and the log is append-only: a
    /// note that doesn't exist is created, and one that does is *appended to*
    /// rather than rewritten. An append is the honest representation of an edit
    /// here — the assistant reads the whole body and the newest text is last,
    /// while the original wording stays in the history where a rewrite would
    /// have destroyed it.
    func saveHouseRules() {
        let text = houseRulesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            if let existing = houseRulesNote {
                try service.appendToNote(id: existing.id, text: text, source: Onboarding.source)
                statusMessage = "Updated “\(existing.title)”."
            } else {
                let title = Autopilot.noteTitle(existingTitles: (notes + archivedNotes).map(\.title))
                // `source: "unlirice"` — the app's own voice, same as the seeded
                // guides. Marking it "human" would make the transaction log lie,
                // even though a human may well have edited the wording.
                let note = try service.createNote(title: title, body: text, source: Onboarding.source)
                try service.tagNote(id: note.id, tag: Autopilot.noteTag, source: Onboarding.source)
                statusMessage = "Saved “\(title)” — your assistant will find it on its next session."
            }
            reload()
        } catch {
            errorMessage = "Couldn't write the house-rules note: \(error)"
        }
    }

    // MARK: - Existing vault

    /// Points the app at a folder that already holds an `events.jsonl`. The
    /// connector table is already on screen when this is reachable, and every
    /// row re-reads its own state when the corpus changes, so there's nowhere
    /// to navigate to afterwards.
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
        connectionResults = []
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
