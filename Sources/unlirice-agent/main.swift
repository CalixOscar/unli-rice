import Foundation
import UnliRiceCore
import UnliRiceHost

/// The part that runs with the window closed.
///
/// launchd starts this every few minutes (see `BackgroundAgent`). It does one
/// tick and exits — there is no loop and no long-lived process. A short-lived
/// process that leaves nothing behind is much easier to reason about than a
/// resident one: it cannot leak, cannot wedge, cannot hold a stale view of
/// settings, and if it crashes the next tick is unaffected.
///
/// It is deliberately incapable of doing anything the buttons in the window
/// can't. `RoutineDriver` is the same code path the GUI heartbeat calls, and the
/// permission boundaries below it (`IngestRunner`, `JanitorRunner`) are enforced
/// by type, not by which process happens to be running. Nothing here can archive
/// a note, resolve a review flag, or delete anything, because no such method
/// exists to call.
///
/// Its whole output is: work done to the corpus through those two runners, plus
/// entries in the notification centre for the human to read later.

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
}

/// `--install` / `--uninstall` / `--status`, so the launchd job can be managed
/// and *diagnosed* without the GUI.
///
/// This earned its place immediately: the first real press of the app's "In
/// background" toggle silently did nothing, and there was no way to see why —
/// the GUI reported the failure into an error banner that panel doesn't render.
/// A one-line command that prints the actual error is the difference between a
/// five-minute fix and guessing.
switch CommandLine.arguments.dropFirst().first {
case "--status":
    print("background job: \(BackgroundAgent.isInstalled() ? "installed" : "not installed")")
    print("plist:          \(BackgroundAgent.plistURL().path)")
    print("agent binary:   \(BackgroundAgent.locateBinary()?.path ?? "not found next to this executable")")
    print("settings:       \(AgentSettings.defaultURL().path)")
    exit(0)

case "--install":
    do {
        try BackgroundAgent.install(
            logDirectory: DataLocation.supportDirectory().appendingPathComponent("logs", isDirectory: true)
        )
        print("installed \(BackgroundAgent.plistURL().path)")
    } catch {
        log("install failed: \(error)")
        exit(1)
    }
    exit(0)

case "--uninstall":
    do {
        try BackgroundAgent.uninstall()
        print("removed")
    } catch {
        log("uninstall failed: \(error)")
        exit(1)
    }
    exit(0)

default:
    break
}

// `--ingest` / `--janitor` run one pipeline immediately, ignoring the schedule
// and the routines switch — the CLI equivalents of the two buttons in the
// window. They exist because the scheduled path is, correctly, hard to trigger
// on demand: `tick` refuses unless routines are on *and* a slot is due, which is
// exactly what you don't want when you've just nominated a folder and would
// like to see it indexed now.
//
// They are still incapable of more than the buttons: both go through the same
// runners, whose permission boundaries are enforced by type. Neither can
// archive, retitle, merge, or delete anything.
switch CommandLine.arguments.dropFirst().first {
case "--ingest", "--janitor", "--preview-ingest":
    let manualSettings = AgentSettings.load()
    let logURL = DataLocation.eventLogURL(persistedFolderPath: manualSettings.dataFolderPath)
    guard let manualStore = try? EventStore(fileURL: logURL) else {
        log("could not open event log at \(logURL.path)")
        exit(1)
    }
    let manualService = NoteService(store: manualStore)
    log("corpus: \(logURL.path)")

    do {
        switch CommandLine.arguments.dropFirst().first {
        case "--janitor":
            let runner = JanitorRunner(service: manualService)
            let report = try runner.run(config: JanitorConfig(autonomy: manualSettings.autonomy))
            log("janitor (\(manualSettings.autonomy)): \(report.summary)")

        default:
            let previewOnly = CommandLine.arguments.dropFirst().first == "--preview-ingest"
            let rawStore = RawStore(directoryURL: RawStore.directoryURL(besideEventLog: logURL))
            let runner = IngestRunner(service: manualService, rawStore: rawStore)
            for importer in Pipelines.standard(scanRoots: manualSettings.scanRoots) {
                if previewOnly {
                    let found = try runner.preview(importer: importer)
                    log("\(importer.identifier): would take \(found.count)")
                    for resource in found { log("    \(resource.title)") }
                } else {
                    log(try runner.run(importer: importer).summary)
                }
            }
        }
    } catch {
        log("failed: \(error)")
        exit(1)
    }
    exit(0)

default:
    break
}

// `--purge` is the one thing in this binary that is *not* an equivalent of a
// button, and the only place outside the GUI that can reach `TrashService`.
//
// It exists because the GUI purge is per-note: it operates on rows ticked in
// the Archived pane, which is the right shape for trashing three notes and an
// unusable one for trashing three hundred. Decision #2's carve-out is about
// *who* triggers a delete, not about which process runs it, so a command a
// person types satisfies it where a routine never could. The guards below are
// what keep that true:
//
//   - the ids come in on stdin, so this cannot select its own victims. Whatever
//     produced the list did the judging, in the open, before this ran.
//   - `--yes` is required. Without it the command prints the titles it would
//     destroy and exits without touching the log, which is also how you preview.
//   - `RoutineDriver` still has no path here, and neither does the MCP catalog.
//     An agent cannot type a command.
if CommandLine.arguments.dropFirst().first == "--purge" {
    let confirmed = CommandLine.arguments.contains("--yes")
    let purgeSettings = AgentSettings.load()
    let logURL = DataLocation.eventLogURL(persistedFolderPath: purgeSettings.dataFolderPath)
    guard let purgeStore = try? EventStore(fileURL: logURL) else {
        log("could not open event log at \(logURL.path)")
        exit(1)
    }
    let notes = Projector.project((try? purgeStore.readAll()) ?? [])

    var ids: Set<UUID> = []
    var unknown = 0
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
        guard let id = UUID(uuidString: trimmed) else { continue }
        if notes[id] == nil { unknown += 1 } else { ids.insert(id) }
    }

    log("corpus: \(logURL.path)")
    log("\(notes.count) notes in the log, \(ids.count) selected\(unknown > 0 ? ", \(unknown) ids not found" : "")")

    guard !ids.isEmpty else {
        log("nothing to purge")
        exit(1)
    }

    guard confirmed else {
        for id in ids { log("    would purge: \(notes[id]?.title ?? id.uuidString)") }
        log("dry run — pass --yes to actually purge")
        exit(0)
    }

    do {
        let receipt = try TrashService.purge(noteIDs: ids, logURL: logURL)
        log("purged \(receipt.notesPurged) notes (\(receipt.eventsRemoved) events)")
        log("\(receipt.eventsRemaining) events remain")
        log("backup: \(receipt.backupURL.path)")
        log("trash:  \(TrashService.trashDirectory(forLog: logURL).path)")
    } catch {
        log("purge failed: \(error)")
        exit(1)
    }
    exit(0)
}

let settings = AgentSettings.load()

// The settings file names the corpus; `DataLocation` resolves it exactly as the
// GUI does, so the two can never end up working on different files while
// believing they're peers. `UNLIRICE_DATA_PATH` still outranks it, which is what
// lets this binary be smoke-tested against a scratch log.
let eventLogURL = DataLocation.eventLogURL(persistedFolderPath: settings.dataFolderPath)

guard let store = try? EventStore(fileURL: eventLogURL) else {
    log("could not open event log at \(eventLogURL.path)")
    exit(1)
}

let service = NoteService(store: store)
let driver = RoutineDriver(service: service, eventLogURL: eventLogURL)
let machine = MachineState.current()

let report = driver.tick(now: Date(), settings: settings, machine: machine)

// Written to the log launchd captures — the only way to find out what happened
// while nobody was watching. Quiet ticks stay one line.
if report.didWork {
    for run in report.ran {
        log("\(run.failed ? "FAILED" : "ran") \(run.kind.rawValue): \(run.summary)")
    }
} else if !settings.routinesEnabled {
    log("routines are off — nothing to do")
} else {
    let holds = report.holds.map { "\($0.key.rawValue): \($0.value)" }.sorted().joined(separator: "; ")
    log("nothing due\(holds.isEmpty ? "" : " (\(holds))")")
}
for notice in report.posted {
    log("notice: \(notice.title)")
}
