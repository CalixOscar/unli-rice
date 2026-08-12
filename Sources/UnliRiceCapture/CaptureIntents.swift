import Foundation
import AppIntents
import UnliRiceCore

/// App Intent for binding voice recording to the iOS Action Button, Shortcuts, or Control Center.
///
/// **A toggle, not a timed sample.** The Action Button delivers one event per
/// press — there is no release callback for an App Intent — so "stop when it is
/// pressed again" is the only shape the hardware allows, and it is also the one
/// the app already uses for tap-to-toggle. Press to start, press to stop.
///
/// The previous implementation slept for three seconds and stopped itself,
/// which is not a short recording so much as a recording that lies: the user
/// keeps talking, and the half it kept is saved as though it were everything.
/// Recording length is deliberately unbounded here for the same reason it is in
/// `Recorder` — see the note there about why nothing in this app ends a
/// recording but the user.
///
/// Runs through `CaptureStore.shared` rather than building its own pipeline, so
/// a capture made with the button is tagged with the open project, indexed for
/// playback, written to the event log, and published to the shared folder on
/// exactly the same path as one made by tapping the mic.
@available(iOS 16.0, *)
public struct RecordCaptureIntent: AppIntent {
    public static var title: LocalizedStringResource = "Record Voice Capture"
    public static var description = IntentDescription("Starts recording a voice capture in Unli Rice. Run it again to stop and save.")
    /// The recording has to outlive `perform()`, which returns immediately after
    /// starting it. `UIBackgroundModes: audio` keeps the process alive to hold
    /// the microphone; the app does not need to come to the front for either
    /// press.
    public static var openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CaptureStore.shared.toggleFromIntent()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

@available(iOS 16.0, *)
public struct CaptureShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordCaptureIntent(),
            phrases: [
                "Capture voice note in \(.applicationName)",
                "Record note in \(.applicationName)"
            ],
            shortTitle: "Record Voice Capture",
            systemImageName: "mic.fill"
        )
    }
}
