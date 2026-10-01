1. **SUSPECTED — Copying helper entitlements does not establish that the extension can resolve the app’s bookmark.**  
   **Evidence:** `Sources/UnliRice/AppStore.swift:848` creates an app-scoped bookmark with `.withSecurityScope` and `relativeTo: nil`; `Sources/UnliRiceCore/CorpusLocation.swift:165` resolves it with `.withSecurityScope`. `UnliRiceHelper.entitlements` supplies entitlements, but no extension execution evidence. The resolver tests inject bookmark resolution rather than exercise real sandbox access. Apple documents restrictions tied to the bookmark creator’s signing identity. [Apple bookmark documentation](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata%28options%3Aincludingresourcevaluesforkeys%3Arelativeto%3A%29).  
   **Failure:** The default App Group corpus works while every custom-folder widget fails, particularly after restarting or installing a differently signed build. The helpers calling this code proves reuse, not successful access from WidgetKit. This requires a signed extension test.

2. **CONFIRMED — B2’s “any failure becomes Unknown” cannot be achieved merely by catching errors from the prescribed calls.**  
   **Evidence:** `AgentSettings.swift:186` silently returns defaults for unreadable or malformed settings. `CorpusLocation.swift:130` returns a default-corpus fallback for failed bookmarks rather than throwing. `DataLocation.swift:103` falls back to Application Support when the group container is unavailable. `unlirice-mcp/main.swift:20` explicitly warns and then continues against that fallback.  
   **Failure:** The widget can confidently show the wrong corpus or “Nothing to do.” B4 can archive a matching UUID in a fallback corpus—for example, a copied corpus—or fail against a missing UUID. The proposed resolver path is not fail-closed.

3. **CONFIRMED — “Open NoteService read-only” names a mode that does not exist, and damaged logs can look empty.**  
   **Evidence:** `NoteService.swift:48` accepts an ordinary `EventStore`; `EventStore.swift:55` creates directories and a missing log. At `EventStore.swift:187`, undecodable event lines are silently discarded.  
   **Failure:** Merely rendering a widget can create a new empty log. A missing log beside an existing snapshot, or corruption that removes relevant events from projection, can produce Empty rather than Unknown. §7 tests neither condition.

4. **CONFIRMED — The running app does not automatically observe a widget write at the UI level.**  
   **Evidence:** `NoteService.swift:222` reads appended bytes when queried, but that is pull-based. `UnliRiceApp.swift:50` ticks every five minutes; `AppStore+Ingest.swift:243` calls `reload()` only when the routine reports work. `RoutineDriver.swift:55` defines work as a nonempty `ran` list. `TodoPaneView.swift:18` retains its own derived state and loads on appearance at line 43.  
   **Failure:** Done disappears from the widget while an already-open To Do pane continues showing it. Even an `AppStore.reload()` does not itself recompute the pane’s private `todo`. Adding widget reload calls after app refreshes only addresses the opposite direction.

5. **SUSPECTED — Cold projection and blocking locks can exceed a widget’s execution resources.**  
   **Evidence:** Every new `NoteService` starts at cursor zero (`NoteService.swift:38`). `EventStore.swift:176` reads the entire remaining file into memory and decodes an event array; `NoteService.swift:228` projects all notes and updates their link index before filtering archived notes at line 177. Reads hold a shared `flock` through decoding; writes acquire a blocking exclusive lock (`EventStore.swift:90,158`).  
   **Failure:** A large ingestion history can make a three-row widget expensive enough to terminate or time out. Its read can also delay MCP writes; its Done action can wait on other readers. The plan supplies no corpus-size, peak-memory, or contention measurements. I have not verified a numerical memory limit for this macOS extension.

6. **CONFIRMED — `flock` protects individual appends, not the meaning of a stale Done action.**  
   **Evidence:** B4 carries only `noteID` and resolves the current corpus at execution. `NoteService.archiveNote`, at `NoteService.swift:98`, checks existence, appends an archive event, and rereads; it checks neither `todo` membership nor current archived state, corpus identity, or revision. Those operations are not one locked transaction.  
   **Failure:** A row rendered before a corpus switch can act on another copy of the note. A delayed tap can rearchive an item someone deliberately reopened, or archive a note whose `todo` tag was removed. Repeated taps append repeated completion events.

7. **CONFIRMED — The proposed prompt URL turns navigation into an externally triggerable clipboard write.**  
   **Evidence:** Plan B5/B6 accepts `unlirice://prompt/<itemNoteID>` and immediately copies. `AppStore+TodoPrompt.swift:79` clears the general pasteboard before writing. The plan specifies no caller distinction, confirmation boundary, strict URL grammar, or requirement that the UUID identify an eligible to-do.  
   **Failure:** Another app with a known item UUID can overwrite the clipboard without a widget interaction. Permissive parsing could accept extra path components, credentials, query strings, or malformed IDs inconsistently. A custom URL scheme does not establish that the request came from the widget.

8. **CONFIRMED — Handoff text becomes instructions without an explicit trust boundary.**  
   **Evidence:** B6 inserts the full item and handoff bodies into an imperative task prompt. `NoteService.swift:69,76` permits creating and appending arbitrary text, and `source` is a supplied string. The existing prompt introduces its contents as work to perform (`AppStore+TodoPrompt.swift:23–33`).  
   **Failure:** A handoff can contain instructions to ignore repository rules, run destructive commands, or archive unfinished work. Copying does not execute these instructions, but pasting into an assistant carries them forward as part of the user’s task. “Check current state first” addresses staleness, not hostile instructions or false provenance.

9. **CONFIRMED — A handoff title is not a stable, unambiguous checkpoint reference.**  
   **Evidence:** `AGENTS.md:191` uses project, minute, and tool in the title; concurrent sessions can generate the same title. `NoteService.swift:69` does not enforce uniqueness. `LinkIndex.swift:72` gives a title to the oldest note, breaking ties by UUID; `AppStore.swift:232` instead chooses the first active match, then an archived match, from lists sorted by update time (`NoteService.swift:177`).  
   **Failure:** Opening a handoff through app lookup can select a different note from the wiki-link graph. Appending to a duplicate can change which note the app selects. “That specific handoff” is not guaranteed.

10. **CONFIRMED — The handoff resolver’s signature cannot implement its documented contract.**  
    **Evidence:** Plan A2 declares `handoffTitle(inBody: String)` but requires knowing whether a target note exists and carries `handoff`; neither notes nor a resolver are inputs. A3 says “the first one wins,” while A2 says the first *resolving handoff* wins. B5 only mentions existence. `WikiLink.swift:21` stops at the first `]]`, with no escaping mechanism.  
    **Failure:** Different implementations can select an ordinary reference, skip a legitimate handoff, or disagree between navigation and prompt generation. Titles containing `]]` cannot round-trip. Old items are not necessarily link-free: an existing ordinary wiki-link could accidentally become a handoff association.

11. **CONFIRMED — The seventh field proves formatting, not completion or even filing.**  
    **Evidence:** `Scripts/lint-memory.sh:75–99` checks field names, order, duplicates, and a date. It does not validate `To-dos` contents, event-log writes, commit evidence, or changed handoff fields. The installed `.git/hooks/pre-commit` runs the content check when `memory.md` is staged and otherwise permits several commits before blocking on age.  
    **Failure:** An agent can leave `none this checkpoint`, fabricate “closed 2,” or supply an unrelated real commit hash and pass. The validator also reads the working-tree file for structural checks, rather than validating the staged blob. “Binds every tool that commits” materially overstates enforcement.

12. **CONFIRMED — The newly permitted archive action remains unrestricted, and the written rules conflict.**  
    **Evidence:** `AGENTS.md:199` forbids closing merely stale or obsolete items, but its final section at line 226 still says archive only when genuinely obsolete. Plan §5 reduces the MCP instruction to “if you finished one, archive it with the reason.” `NoteService.swift:98` accepts any existing note and arbitrary reason/source; no evidence validation exists.  
    **Failure:** An agent can misuse archive as cleanup or hide unfinished work while producing a convincing audit reason. Founder authorization for narrow completion does not make the narrowness technically enforced. Soft reversibility helps recovery only after someone notices.

13. **CONFIRMED — `availableTargets.first` does not mean “first configured target.”**  
    **Evidence:** `AppStore+Autopilot.swift:19` returns `MCPTarget.builtIn + customTargets`. `MCPTarget.swift:69` always starts with Claude Code. `AppStore+TodoPrompt.swift:26` instructs the receiving assistant to use the selected target’s source identity.  
    **Failure:** A Codex-only user receives a Claude Code prompt telling Codex to write as `claude`. The no-configured-target fallback is unreachable through this property. The retained template also falsely says MCP is connected, attributes the task to `memory.md`, and still requires “all six fields” (`AppStore+TodoPrompt.swift:23,29,75`).

14. **SUSPECTED — “The main window” is not a defined routing destination in this app.**  
    **Evidence:** `UnliRiceApp.swift:30,39` has one shared `AppStore` and a `WindowGroup`, not one uniquely identified window. B5 attaches `.onOpenURL` to window content without specifying cold launch, closed-window reopening, or multiple-window handling. `AppStore.note(id:)` reads a cached index (`AppStore.swift:1058`).  
    **Failure:** A link may navigate shared state across windows or be handled before a newly filed item is in the cache. The user can land in the wrong visible window or fail to open an item the widget already displays. Actual delivery behavior needs running-app verification.

15. **CONFIRMED — Re-keying is safe for ordinary mixed-case names, but not demonstrably behavior-preserving for all inputs.**  
    **Evidence:** `StudioTodo.swift:301` concatenates entries under both the lowercase and exact repo name. Current pane filters populate lowercase keys (`TodoPaneView.swift:237`; Capture `TodoView.swift:264`).  
    **Failure:** With snapshot names `Foo` and `foo`, populating exact-name keys can make `Foo` consume both buckets and duplicate items. An implementation that chooses only one matching repo instead loses an association. Independently, flattening multi-project buckets produces multiple rows for one note; Done archives all appearances, while the URL contains no project to identify which repo context belongs in the prompt. A3 does not cover these cases.

16. **CONFIRMED — A readable but stale snapshot can hide real to-dos and produce a false empty state.**  
    **Evidence:** B2 filters notes through snapshot `repoNames`. `RepoSnapshotFile.swift:245` validates readability/schema, not freshness; `isStale` exists separately at line 202. The planned tests explicitly exclude unknown project tags.  
    **Failure:** A new or renamed project absent from `repos.json` has its valid items silently removed. An empty snapshot can yield “Nothing to do” while open to-do notes exist. This inherits an existing pane limitation but conflicts with the widget’s promise to show items across all projects.

17. **CONFIRMED — “Within 15 minutes” is not guaranteed by `.after`.**  
    **Evidence:** Plan B2 and §7 make that promise. Apple describes timeline reloads as system-scheduled and budgeted, not a maximum-latency guarantee. [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).  
    **Failure:** Correct implementation can fail the acceptance test, and users can see stale tasks longer than promised. Debugger-attached testing is insufficient evidence of production refresh timing.

18. **CONFIRMED — The handoff workflow has gaps for disconnected tools, chat apps, and later checkpoints.**  
    **Evidence:** `AGENTS.md:207` permits recording “would have filed” locally when MCP is unavailable, without a later reconciliation mechanism. Plan §5’s three MCP sentences omit creating/tagging a handoff and linking it. `unlirice-mcp/main.swift:83` currently contains none of this workflow. No Unli Rice MCP tools are exposed in this review session.  
    **Failure:** Deferred work remains outside the widget indefinitely. Chat clients can comply with their short instructions while creating items without handoffs. Existing items remain linked to an earlier checkpoint after subsequent work; copied handoff bodies can also acquire later appended material (`NoteService.swift:76`), so they are not immutable snapshots.

19. **CONFIRMED — §7 can pass while important changed surfaces remain untested.**  
    **Evidence:** `Package.swift:75` tests Core and Host, not the app’s prompt implementation. The widget is absent from SwiftPM. §7 requests the Mac Xcode scheme but changes shared code and Capture’s pane. The existing three-second to-do feedback is local menu state (`TodoPaneView.swift:281,303`), not a global confirmation available automatically after navigation.  
    **Failure:** Green core tests do not establish URL parsing, clipboard behavior, Capture compilation, app–widget agreement, or the promised confirmation. Missing cases include concurrent writes, malformed/truncated logs, settings failure, duplicate titles, corpus switches, malicious URLs, and repeated Done. Signed bookmark access after restart, extension termination under load, production refresh timing, multi-window routing, macOS 13 installation behavior, and layout/accessibility require integration or hands-on checks.

20. **CONFIRMED — The plan mixes superseded baseline claims with already-landed work and an inconsistent change whitelist.**  
    **Evidence:** `git rev-parse --short HEAD` returns `5460f64`; that commit already changes `AGENTS.md`, both linters, and `memory.md`. The plan’s §1 still describes six fields and forbidden agent closure. §7’s whitelist omits the MCP instructions change and documentation/tooling edits. `.gitignore:4` ignores generated `*.xcodeproj`.  
    **Failure:** A literal implementation can redo completed contract work or omit necessary changes to satisfy the whitelist. A normal tracked `git diff` cannot establish that the ignored generated project contains the extension. Claims about vault copies, six other repositories, guide contents, and installed hooks elsewhere are not established by this repository’s history.

Claims verified as correct:

- `1b4779a` introduced AI-filed to-dos on Mac and Capture; both currently archive through `NoteService`.
- The two pane filters are identical, and `derive` accepts both lowercase and exact-name keys.
- EventStore uses exclusive append locks and shared read locks; NoteService incorporates external appends on subsequent reads.
- The default location uses the named App Group when available, and AgentSettings stores the custom-folder bookmark.
- The Mac deployment floor is 13.0; no URL scheme or `onOpenURL` handler exists in the inspected source/configuration.
- The seventh field and narrow agent-closure instructions have already landed at `5460f64`. No files were modified during this review.