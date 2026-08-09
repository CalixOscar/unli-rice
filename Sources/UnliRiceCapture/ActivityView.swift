import SwiftUI
import UIKit

/// A thin wrapper around `UIActivityViewController`.
///
/// Used instead of SwiftUI's `ShareLink` in `AISharePreviewView`: on this
/// build, `ShareLink` — like a plain `Button` composed the way this app's
/// controls are — did not reliably receive taps (confirmed on-device; see
/// `CaptureView.sendToAIBar`, which has the same story). Presenting the OS
/// share sheet by hand, triggered from a plain `onTapGesture`, is the pattern
/// that's proven reliable everywhere else in this app, so this exists to keep
/// that pattern rather than fight `ShareLink`.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
