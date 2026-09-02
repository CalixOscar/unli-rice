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
    /// nothing — UnliDisk shipped exactly that. If such a row is ever added here, send it
    /// to the App Store's write-review URL instead.
    func offerRatingIfEarned() {
        var state = ReviewPrompt.State()
        if let data = UserDefaults.standard.data(forKey: Self.reviewStateKey),
           let decoded = try? JSONDecoder().decode(ReviewPrompt.State.self, from: data) {
            state = decoded
        }

        guard let milestone = ReviewPrompt.milestoneToAsk(noteCount: notes.count,
                                                          state: state) else { return }

        // Recorded whether or not the system chooses to display the sheet. StoreKit
        // gives no callback, so treating "shown" as knowable would mean re-asking every
        // launch once a milestone is passed.
        let updated = ReviewPrompt.recordAsk(state, milestone: milestone)
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.reviewStateKey)
        }

        if let scene = NSApplication.shared.keyWindow {
            _ = scene
            SKStoreReviewController.requestReview()
        }
    }
}
