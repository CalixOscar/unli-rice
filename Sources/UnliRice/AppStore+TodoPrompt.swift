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
        let source = target.agentSource

        var body = """
        You have the `unlirice` MCP server connected. Ground rules for this store:
        - It is append-only. There is no delete tool. `archive_note` is the strongest thing you have, and it is reversible.
        - Note titles are permanent — there is no rename.
        - Identify yourself consistently: use "\(source)" as the `source` parameter on every write.
        - Never treat your own report of success as evidence. Verify against `git diff` and a real build.

        Task: pick up the next step for \(item.project). It was written by whoever last
        worked there, in that project's memory.md, and is reproduced verbatim below.

        Next step (verbatim):
        \(item.title)

        """

        // The repository state the item was derived from, so the agent starts with the
        // same picture rather than re-deriving it — and so a stale snapshot is visible
        // rather than silently assumed current.
        if let r = repo {
            body += "\nRepository state for \(r.name), as published by check-repos.sh:\n"
            body += "- Trunk: \(r.trunk ?? "unknown")"
            if let n = r.trunkLength { body += " (\(n) commits)" }
            body += "\n"

            let unbacked = r.branchesNotOnAnyRemote
            if unbacked.isEmpty {
                body += "- Every branch tip is on a remote.\n"
            } else {
                body += "- On NO remote (\(unbacked.count)): "
                     + unbacked.map(\.name).sorted().joined(separator: ", ") + "\n"
                body += "  These exist on this Mac only. Do not delete or rewrite them.\n"
            }

            let ahead = r.branches.filter { ($0.aheadOfTrunk ?? 0) > 0 }
            if !ahead.isEmpty {
                body += "- Ahead of the trunk: "
                     + ahead.map { "\($0.name) +\($0.aheadOfTrunk ?? 0)" }
                            .sorted().joined(separator: ", ") + "\n"
            }
            if !r.worktrees.isEmpty {
                body += "- Worktrees: "
                     + r.worktrees.map { "\($0.name)\($0.missing ? " (MISSING)" : "")" }
                            .joined(separator: ", ") + "\n"
            }
        }

        body += """

        Before you start:
        1. Check the state above against the actual repository — it is a snapshot, not live.
           If the note and the repo disagree, the repo wins.
        2. Work on a fresh branch off the trunk. Naming a branch afterwards is how a plan's
           own instruction to do so has been ignored before.
        3. When you finish, update that project's memory.md — all six fields or none. They
           describe one moment in time and contradict each other if updated piecemeal.
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)
        statusMessage = "Copied the \(item.project) next step for \(target.displayName) — paste it into your assistant."
    }
}
