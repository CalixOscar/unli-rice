import AppKit
import Foundation
import UnliRiceCore

struct TrustCheck: Identifiable, Equatable {
    enum State: Equatable {
        case healthy
        case attention
        case failed
    }

    let id: String
    let title: String
    let detail: String
    let state: State
}

extension AppStore {
    /// Refreshes operational evidence without writing to the vault.
    func refreshTrustCenter() {
        var connectionActivityError: Error?
        do {
            connectionActivities = try MCPConnectionActivityStore(besideEventLog: dataURL).list()
        } catch {
            connectionActivities = []
            connectionActivityError = error
        }
        vaultSnapshots = VaultSnapshotService.list(logURL: dataURL)
        trashedNotes = TrashService.listTrashed(forLog: dataURL)

        var checks: [TrustCheck] = []
        do {
            let events = try service.transactionLog(limit: .max)
            checks.append(TrustCheck(
                id: "event-log",
                title: "Event log opens",
                detail: "\(events.count) immutable event\(events.count == 1 ? "" : "s") at \(dataURL.path)",
                state: .healthy
            ))
        } catch {
            checks.append(TrustCheck(
                id: "event-log",
                title: "Event log could not be read",
                detail: error.localizedDescription,
                state: .failed
            ))
        }

        let writable = FileManager.default.isWritableFile(atPath: dataURL.deletingLastPathComponent().path)
        checks.append(TrustCheck(
            id: "writable",
            title: writable ? "Vault is writable" : "Vault is read-only",
            detail: writable
                ? "Assistants and the app can append new events."
                : "New memories cannot be saved at this location.",
            state: writable ? .healthy : .failed
        ))

        if let connectionActivityError {
            checks.append(TrustCheck(
                id: "mcp-client",
                title: "Connection activity could not be read",
                detail: connectionActivityError.localizedDescription,
                state: .failed
            ))
        } else if let latest = connectionActivities.first {
            let detail: String
            let state: TrustCheck.State
            let title: String
            if let tool = latest.lastToolName, let calledAt = latest.lastToolCallAt {
                detail = "\(latest.clientName) called \(tool) \(calledAt.formatted(.relative(presentation: .named)))."
                state = latest.lastToolSucceeded == false ? .attention : .healthy
                title = "An MCP client has checked in"
            } else if let deliveredAt = latest.lastContextDeliveredAt {
                // Vault Mode: the agent reads Markdown off disk, which nothing
                // here can see. Delivery is the strongest true claim available,
                // so make it rather than crying wolf about a read we can't watch.
                detail = "\(latest.clientName) was given the vault context \(deliveredAt.formatted(.relative(presentation: .named))). Reading files isn't observable from here."
                state = .healthy
                title = "Vault context delivered"
            } else {
                detail = "\(latest.clientName) has been connected \(latest.lastSeenAt.formatted(.relative(presentation: .named))), but has never read a note."
                state = .attention
                title = "MCP client connected but has not read notes"
            }
            checks.append(TrustCheck(
                id: "mcp-client",
                title: title,
                detail: detail,
                state: state
            ))
        } else {
            checks.append(TrustCheck(
                id: "mcp-client",
                title: "No MCP client has checked in yet",
                detail: "Reconnect or restart a configured assistant, then ask it to search Unli Rice.",
                state: .attention
            ))
        }

        if let latest = vaultSnapshots.first {
            checks.append(TrustCheck(
                id: "snapshot",
                title: "Recovery point available",
                detail: "Latest: \(latest.createdAt.formatted(.relative(presentation: .named))) · \(latest.eventCount) events.",
                state: .healthy
            ))
        } else {
            checks.append(TrustCheck(
                id: "snapshot",
                title: "No recovery point yet",
                detail: "Create one before making large changes to this vault.",
                state: .attention
            ))
        }

        checks.append(TrustCheck(
            id: "background",
            title: backgroundAgentInstalled ? "Background checks are installed" : "Background checks stop with the window",
            detail: backgroundAgentInstalled
                ? "The launch agent can serve scheduled routines while Unli Rice is closed."
                : "This is safe; scheduled work simply requires the app to remain open.",
            state: backgroundAgentInstalled ? .healthy : .attention
        ))
        trustChecks = checks
    }

    func createRecoveryPoint() async {
        guard !trustBusy else { return }
        trustBusy = true
        trustMessage = "Creating and verifying a recovery point…"
        defer { trustBusy = false }
        let logURL = dataURL
        do {
            let snapshot = try await Task.detached {
                try VaultSnapshotService.create(logURL: logURL)
            }.value
            trustMessage = "Verified \(snapshot.eventCount) events across \(snapshot.files.count) files."
            refreshTrustCenter()
        } catch {
            trustMessage = "Recovery point failed: \(error.localizedDescription)"
        }
    }

    func verifyRecoveryPoint(_ snapshot: VaultSnapshot) async {
        guard !trustBusy else { return }
        trustBusy = true
        trustMessage = "Verifying every file in \(snapshot.id)…"
        defer { trustBusy = false }
        let logURL = dataURL
        do {
            try await Task.detached {
                try VaultSnapshotService.verify(snapshot, logURL: logURL)
            }.value
            trustMessage = "Verified \(snapshot.files.count) files — the recovery point is intact."
        } catch {
            trustMessage = "Verification failed: \(error.localizedDescription)"
        }
    }

    func restoreRecoveryPoint(_ snapshot: VaultSnapshot) async {
        guard !trustBusy else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore missing history from this recovery point?"
        alert.informativeText = "Unli Rice will verify it first, then append only event IDs and raw files missing from the current vault. Nothing current will be replaced."
        alert.addButton(withTitle: "Restore Missing History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        trustBusy = true
        trustMessage = "Verifying and merging missing history…"
        defer { trustBusy = false }
        let logURL = dataURL
        do {
            let receipt = try await Task.detached {
                let store = try EventStore(fileURL: logURL)
                return try VaultSnapshotService.restore(snapshot, logURL: logURL, into: store)
            }.value
            reload()
            refreshTrustCenter()
            trustMessage = receipt.eventsAppended == 0 && receipt.rawFilesRestored == 0
                ? "The vault already contains everything in that recovery point."
                : "Restored \(receipt.eventsAppended) events and \(receipt.rawFilesRestored) raw files."
        } catch {
            trustMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    func restoreFromTrash(_ record: TrashService.TrashedNote) {
        let alert = NSAlert()
        alert.messageText = "Restore “\(record.title)”?"
        alert.informativeText = "Its complete event history will be appended back into the current vault."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let store = try EventStore(fileURL: dataURL)
            try TrashService.restore(noteID: record.noteID, logURL: dataURL, into: store)
            reload()
            refreshTrustCenter()
            trustMessage = "Restored “\(record.title)” with \(record.events.count) events."
        } catch {
            trustMessage = "Trash restore failed: \(error.localizedDescription)"
        }
    }

    func revealRecoveryPoints() {
        let url = VaultSnapshotService.directory(forLog: dataURL)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func noteHistory(_ note: Note) -> [Event] {
        (try? service.noteHistory(id: note.id)) ?? []
    }

    func provenance(_ note: Note) -> NoteProvenance {
        NoteProvenance.parse(note.body)
    }

    func revealRawSource(for note: Note) {
        guard let url = provenance(note).rawURL(besideEventLog: dataURL),
              FileManager.default.fileExists(atPath: url.path)
        else {
            statusMessage = "The raw source for “\(note.title)” is not available."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealOriginalSource(for note: Note) {
        guard let path = provenance(note).sourceFilePath,
              FileManager.default.fileExists(atPath: path)
        else {
            statusMessage = "The original source file for “\(note.title)” is not available at its recorded path."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
