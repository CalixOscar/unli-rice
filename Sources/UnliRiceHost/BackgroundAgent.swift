import Foundation

public enum BackgroundAgentError: Error, CustomStringConvertible {
    case binaryNotFound
    case launchctlFailed(String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "Background work needs the packaged app. Run Scripts/make-app.sh and open Unli Rice.app."
        case .launchctlFailed(let detail):
            return "launchctl refused the job: \(detail)"
        }
    }
}

/// Installing and removing the launchd job that keeps the routines running with
/// the window closed.
///
/// **This is the difference between the automation working and looking like it
/// works.** Until it existed, `AppStore.tickRoutines` fired from a SwiftUI
/// `.task` attached to the window, so an app advertising unattended maintenance
/// did none of it the moment you closed the window — which is most of the time,
/// for a thing whose whole pitch is that you shouldn't have to visit it.
///
/// A **LaunchAgent**, not a daemon: it runs as the user, with the user's own
/// file permissions, and can be removed by deleting one plist. Nothing here
/// needs root, asks for root, or would work any better with it.
///
/// ## Why not `SMAppService`
///
/// `SMAppService.agent(plistName:)` is the modern API and was tried here. It
/// **fails on this app**: `register()` returns `SMAppServiceErrorDomain Code=1
/// "Operation not permitted"`, because that API requires a properly signed
/// application and this one is ad-hoc signed (`codesign --sign -`), which is all
/// `Scripts/make-app.sh` can do without a Developer ID. If this project ever
/// gets a real signing identity, `SMAppService` is the better route — it puts
/// the job in System Settings › Login Items where a user can find it. Until
/// then it is strictly worse than this: an API that cannot register.
///
/// Writing the plist directly was also *verified* to work from the real
/// double-clicked app, not assumed — a probe from inside the running bundle
/// listed and wrote `~/Library/LaunchAgents` successfully. That check exists
/// because the folder looks like the sort of thing macOS protects, and a wrong
/// guess about it sent this file through one entirely unnecessary rewrite.
public enum BackgroundAgent {
    public static let label = "com.unlirice.agent"

    /// How often launchd starts it. The same coarse beat the in-window timer
    /// used, and for the same reason: the scheduler asks "has this slot passed
    /// unserved", so a late check serves a slot as well as a punctual one.
    ///
    /// `StartInterval` rather than `StartCalendarInterval` deliberately. A
    /// calendar job fires at a wall-clock time and, if the Mac is asleep then,
    /// launchd runs it once on wake — which sounds equivalent but couples
    /// catch-up behaviour to launchd's rules instead of to `lastFiring`, the one
    /// piece of this that has tests.
    public static let interval = 300

    public static func plistURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    public static func isInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        FileManager.default.fileExists(atPath: plistURL(home: home).path)
    }

    /// Where the agent binary is, given where this process is running from.
    ///
    /// Handles both shapes this project ships in: a `.app` bundle
    /// (`Contents/MacOS/unlirice-agent`, next to the GUI executable) and a bare
    /// `swift build` product, where every executable lands in one directory.
    /// Returns nil rather than a guess — a launchd job pointing at a path that
    /// doesn't exist installs perfectly happily and then does nothing forever,
    /// which is precisely the silent failure this feature exists to remove.
    public static func locateBinary(
        near executable: URL? = Bundle.main.executableURL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let executable else { return nil }
        let candidate = executable.deletingLastPathComponent().appendingPathComponent("unlirice-agent")
        return fileManager.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    /// The launchd job description. Pure, so a test can assert its contents
    /// without installing anything on the machine running the test.
    public static func plist(binary: URL, interval: Int = BackgroundAgent.interval, logDirectory: URL) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [binary.path],
            "StartInterval": interval,
            // Runs once at login too, so a Mac that was off at 09:00 on Tuesday
            // catches the slot up as soon as it's back rather than waiting for
            // the first interval to elapse.
            "RunAtLoad": true,
            // Not a background-priority job: it does real filesystem work and
            // being throttled into never finishing is indistinguishable from
            // being broken. It gates on power and idle time itself.
            "ProcessType": "Standard",
            "StandardOutPath": logDirectory.appendingPathComponent("agent.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("agent.log").path
        ]
    }

    /// Writes the plist and asks launchd to load it. Idempotent: installing over
    /// an existing job replaces it.
    public static func install(
        binary: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        logDirectory: URL
    ) throws {
        guard let binary = binary ?? locateBinary() else { throw BackgroundAgentError.binaryNotFound }

        let url = plistURL(home: home)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist(binary: binary, logDirectory: logDirectory),
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)

        // Unload first so a re-install picks up a changed path. Failure is
        // expected and ignored when nothing was loaded.
        _ = try? launchctl(["bootout", serviceTarget()])
        let result = try launchctl(["bootstrap", domainTarget(), url.path])
        guard result.status == 0 else {
            // The plist is on disk and correct, so the job will load at next
            // login regardless — but say so rather than reporting success,
            // because "it'll start working tomorrow" and "it's working now" are
            // different answers to the only question this toggle asks.
            throw BackgroundAgentError.launchctlFailed(
                result.output.isEmpty ? "exit \(result.status)" : result.output
            )
        }
    }

    /// Removes the job and its plist. Leaves the log alone — it's the only
    /// record of what ran while nobody was watching.
    public static func uninstall(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        _ = try? launchctl(["bootout", serviceTarget()])
        let url = plistURL(home: home)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Private

    /// `bootstrap` takes the *domain* and a path; `bootout` takes the fully
    /// qualified *service*. Passing either one where the other belongs fails
    /// with a bare "Input/output error", which is not a message anyone debugs
    /// quickly — hence two named helpers rather than one string.
    private static func domainTarget() -> String { "gui/\(getuid())" }

    private static func serviceTarget() -> String { "gui/\(getuid())/\(label)" }

    @discardableResult
    private static func launchctl(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
