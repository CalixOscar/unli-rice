import Foundation
import UnliRiceCore
import UnliRiceHost

/// Running with the window closed.
///
/// The gap this closes: the routine heartbeat used to be a SwiftUI `.task`
/// attached to the window, so everything this app said about unattended
/// maintenance was only true while you were looking at it. For an app whose
/// pitch is "you shouldn't have to visit me", that's the difference between the
/// automation working and looking like it works.
extension AppStore {
    /// Whether this copy can do background work at all — i.e. can it find the
    /// agent binary, which in practice means "is this the packaged app".
    var backgroundAgentBinaryFound: Bool {
        BackgroundAgent.locateBinary() != nil
    }

    /// Where launchd writes the agent's output. App-scoped, not corpus-scoped —
    /// it's a log of what the *agent* did, and it should survive pointing the
    /// app at a different vault.
    static var agentLogDirectory: URL {
        DataLocation.supportDirectory().appendingPathComponent("logs", isDirectory: true)
    }

    func setBackgroundAgent(enabled: Bool) {
        do {
            if enabled {
                // Settings are written first, deliberately: launchd starts the
                // job immediately (`RunAtLoad`), and an agent that read a stale
                // file on its first tick would decide it had nothing to do and
                // then wait five minutes to find out otherwise.
                syncAgentSettings()
                try BackgroundAgent.install(logDirectory: Self.agentLogDirectory)
                statusMessage = "Unli Rice will keep working with the window closed."
            } else {
                try BackgroundAgent.uninstall()
                statusMessage = "Background work is off. Routines now only run while this window is open."
            }
            backgroundAgentFailure = nil
        } catch {
            // Shown next to the toggle, not only in `errorMessage` — that banner
            // renders in the note list, which is not the screen you are looking
            // at when you press this.
            backgroundAgentFailure = "\(error)"
            errorMessage = "\(error)"
        }

        // Always republished, even when the answer is unchanged.
        //
        // This is the actual bug the first real press of this toggle hit: a
        // failed install left `backgroundAgentInstalled` false → false, so
        // nothing published, so SwiftUI never re-rendered — and the toggle sat
        // there looking *on* while no job existed. A control that lies about
        // whether the app keeps working with the window closed is worse than no
        // control at all, given that "did it really run?" is the exact question
        // this whole feature exists to answer.
        objectWillChange.send()
        backgroundAgentInstalled = BackgroundAgent.isInstalled()
    }
}
