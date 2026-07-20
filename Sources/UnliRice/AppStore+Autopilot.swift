import AppKit
import Foundation
import UnliRiceCore

/// Get Started, rebuilt around connecting an MCP client.
///
/// The previous design interviewed the user with the local model and handed
/// them a prompt to paste elsewhere. It was cut after a real run: Qwen ended the
/// interview after one answer, and the artifact came out with no stack, no tool
/// and no conventions in it. Nothing in this file calls a model. Every step is
/// deterministic, which is also why all of it is testable.
///
/// App Store builds never write another app's configuration. Every target uses
/// the same explicit copy-and-paste flow, leaving the final edit under the
/// user's control and keeping the app inside its sandbox.
extension AppStore {
    /// Catalog plus anything the user added by hand.
    var availableTargets: [MCPTarget] { MCPTarget.builtIn + customTargets }

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
    }

    // MARK: - Connecting

    /// Copies one complete configuration block without reading or modifying the
    /// destination file. This is the only connection action exposed by the App
    /// Store build.
    func copyConfiguration(for target: MCPTarget) {
        copySnippet(snippet(for: target))
        markGetStartedComplete()
        statusMessage = "Configuration copied for \(target.displayName). Paste it into the file shown, then restart \(target.displayName)."
    }

    /// The paste block for a target, for the tools we don't write to.
    func snippet(for target: MCPTarget) -> String {
        MCPConfigRenderer.snippet(
            for: target.format,
            entry: mcpServerEntry
        )
    }

    private var mcpServerEntry: MCPServerEntry {
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            return .forInstalledApp(at: Bundle.main.bundleURL)
        }
        return .forPackage(
            at: Autopilot.detectedPackageRoot(), dataPathOverride: mcpDataPathOverride
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
        panel.title = "Switch to a different note store"
        panel.message = """
        Pick a folder containing an events.jsonl written by Unli Rice. \
        This replaces which notes the app shows — it is NOT how you add a folder \
        of documents to index; that lives under Automation → Data pipelines.
        """
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        // The bug this guards against, seen for real: pick any folder — a
        // projects directory, the repo itself — and `EventStore.init` creates
        // `events.jsonl` there because that's what it does when the file is
        // missing. The app then showed an entirely empty store with no
        // explanation, and picking a *different* wrong folder to "go back"
        // simply made a second empty one. The notes were never touched; there
        // was just nothing on screen saying where they'd gone.
        //
        // So: starting an empty store is still allowed, but it has to be asked
        // for, and the alert names the path the current notes are actually at.
        let candidate = DataLocation.eventLogURL(inFolder: folder)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "“\(folder.lastPathComponent)” has no notes in it."
            alert.informativeText = """
            There's no events.jsonl in \(folder.path), so continuing gives you an \
            empty app: a brand-new store starts there and your \
            \(notes.count + archivedNotes.count) existing notes stop being shown.

            They are not moved, changed, or deleted — they stay at \(dataURL.path), \
            and “Use the default location” brings them back.

            If you meant to index the documents in this folder, cancel and use \
            Automation → Data pipelines → Add a folder to index instead.
            """
            // Cancel is the default button: the overwhelmingly likely reason to
            // be here with an empty folder is having wanted the other feature.
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Start an Empty Store")
            // Second, not first — Cancel is now the default button above.
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }

        guard switchDataFolder(to: folder) else { return }
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
