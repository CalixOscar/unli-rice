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
