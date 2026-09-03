import SwiftUI

@main
struct CaptureApp: App {
    init() {
        // Counts this launch so the rating prompt can honour "never in the first
        // session". Records nothing else and shows nothing.
        CaptureReviewPrompt.markSessionStart()
    }

    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
    }
}
