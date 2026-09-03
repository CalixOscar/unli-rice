import Foundation
import StoreKit
import UnliRiceCore

extension AppStore {

    private static let reviewStateKey = "unliRice.reviewPromptState"

    /// Offer the system rating sheet, if this is a moment worth spending one on.
    ///
    /// `ReviewPrompt` decides; this only persists the outcome and calls StoreKit. The
    /// split exists so the rule can be tested without burning a real prompt — Apple
    /// allows three per 365 days and silently drops the rest, so there is no way to
    /// exercise this by hand.
    ///
    /// `requestReview` is the right call for an automatic prompt *because* it is
    /// rate-limited: the system decides whether to actually show anything, which is what
    /// keeps an app from nagging. It is the wrong call for a user-tapped "Rate this app"
    /// row, where it fails silently and the person is left staring at a button that did
    /// nothing — UnliDisk shipped exactly that. The "Rate Unli Rice" row in More sends
    /// people to ``writeReviewURL`` instead.
    func offerRatingIfEarned() {
        let state = Self.loadReviewState()

        guard let milestone = ReviewPrompt.milestoneToAsk(noteCount: notes.count,
                                                          state: state) else { return }

        // Ask first, record second. Recording before a call that might not happen is how
        // a rung gets spent on a prompt nobody saw — and there is no way to notice,
        // because the milestone is then permanently marked used.
        SKStoreReviewController.requestReview()

        // But recorded whether or not the system chose to *display* it. StoreKit gives no
        // callback by design, so treating "shown" as knowable would mean re-asking on
        // every launch once a milestone is passed — the nagging this exists to prevent.
        Self.saveReviewState(ReviewPrompt.recordAsk(state, milestone: milestone))
    }

    /// Unli Rice on the Mac App Store, for the permanent "Rate Unli Rice" row in More.
    ///
    /// A deliberate tap must not go through `requestReview`: the OS rate-limits that call
    /// and drops it silently, so the row would be a button that usually did nothing.
    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id6792837485?action=write-review")!
    }

    /// Call once per process launch, before anything can ask. Counts the launch so the
    /// first session can never prompt; shows nothing itself.
    static func markReviewSessionStart() {
        saveReviewState(ReviewPrompt.recordSessionStart(loadReviewState()))
    }

    private static func loadReviewState() -> ReviewPrompt.State {
        guard let data = UserDefaults.standard.data(forKey: reviewStateKey),
              let decoded = try? JSONDecoder().decode(ReviewPrompt.State.self, from: data)
        else { return ReviewPrompt.State() }
        return decoded
    }

    private static func saveReviewState(_ state: ReviewPrompt.State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: reviewStateKey)
    }
}
