import AppKit
import Foundation
import UnliRiceCore

extension AppStore {

    /// Copies a prompt for one to-do item, for whichever tool the user intends to use.
    ///
    /// The same contract as `copyReviewPrompt`: it copies text and nothing else. The app
    /// is sandboxed and cannot run `Process`, so it could not push a branch or delete a
    /// ref even if the button implied it — and locked decision #3 is propose, never
    /// apply. A button that hands you a prompt is honest about that; one labelled as
    /// though the app performs the fix would not be.
    ///
    /// Offered only on *declared* items — the next step someone wrote in memory.md.
    /// At-risk and clutter items already carry an exact command, and routing a known
    /// `git push --all` through an agent is slower and strictly riskier than pasting it.
    func copyTodoPrompt(for target: MCPTarget, item: StudioTodo.Item,
                        repo: RepoSnapshotFile.Repo?) {
        let note = item.noteID.flatMap { self.note(id: $0) }
        let handoff = note.flatMap { itemNote in
            TodoHandoff.handoffID(inBody: itemNote.body).flatMap { self.note(id: $0) }
        }
        let body = TodoPrompt.build(
            target: target,
            item: item,
            itemNote: note,
            handoff: handoff,
            repo: repo
        )

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)
        statusMessage = "Copied the \(item.project) next step for \(target.displayName) — paste it into your assistant."
    }
}
