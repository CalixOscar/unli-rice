import Foundation
import StoreKit
import UIKit
import UnliRiceCore

/// Asks for a rating at the only moment Capture has actually earned one.
///
/// The trigger is a capture reaching **durable success** — the point
/// `CaptureStore.saveCapturedText` defines as such: every event in the batch is in
/// `events.jsonl` and the note is on its way to the Mac. Not "recording stopped", which
/// can still fail; not a launch; not a timer. A thought that got out of someone's head
/// and safely into their memory is the thing this app is for.
///
/// The rule lives in ``ReviewPrompt`` in UnliRiceCore, shared with the Mac app so the two
/// cannot drift into different definitions of "has earned it". Only the rungs differ:
/// a phone capture is a thirty-second voice note, so ``ReviewPrompt/captureMilestones``
/// counts in tens rather than hundreds.
///
/// Deliberately not a custom sheet, and never a "how are you finding it?" pre-screen —
/// routing only happy users to the store is review manipulation under App Store Review
/// Guideline 1.1.7.
@MainActor
enum CaptureReviewPrompt {

    private static let stateKey = "unliRiceCapture.reviewPromptState"
    private static let captureCountKey = "unliRiceCapture.durableCaptureCount"

    /// Unli Rice Capture on the App Store, for the permanent "Rate Unli Rice Capture" row
    /// in Capture Settings.
    ///
    /// A deliberate tap must not go through `requestReview`: the OS rate-limits that call
    /// and drops it silently, leaving a row that usually does nothing when pressed.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6800863948?action=write-review")!

    /// Call once per process launch, before anything can ask. Counts the launch so the
    /// first session can never prompt; shows nothing itself.
    nonisolated static func markSessionStart() {
        save(ReviewPrompt.recordSessionStart(load()))
    }

    /// Call when a capture has durably saved — spoken or typed, both take the same path.
    ///
    /// Usually does nothing: the ladder, the 120-day floor and the three-per-install cap
    /// all have to agree first.
    static func recordDurableCapture() {
        let count = UserDefaults.standard.integer(forKey: captureCountKey) + 1
        UserDefaults.standard.set(count, forKey: captureCountKey)

        let state = load()
        guard let milestone = ReviewPrompt.milestoneToAsk(
            noteCount: count,
            state: state,
            milestones: ReviewPrompt.captureMilestones
        ) else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        SKStoreReviewController.requestReview(in: scene)

        // Recorded whether or not the system chooses to *display* the sheet. StoreKit
        // gives no callback by design, so treating "shown" as knowable would mean
        // re-asking on every capture once a rung is passed — the nagging this prevents.
        save(ReviewPrompt.recordAsk(state, milestone: milestone))
    }

    nonisolated private static func load() -> ReviewPrompt.State {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let decoded = try? JSONDecoder().decode(ReviewPrompt.State.self, from: data)
        else { return ReviewPrompt.State() }
        return decoded
    }

    nonisolated private static func save(_ state: ReviewPrompt.State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}
