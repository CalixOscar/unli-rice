import Foundation
import LocalAuthentication

/// Face ID / Touch ID / passcode gate for the capture list.
///
/// **Uses the device owner's own credentials, and stores no secret of its own.**
/// `.deviceOwnerAuthentication` gives Face ID with an automatic fallback to the
/// device passcode, which is both halves of "a code and Face ID" without this
/// app ever holding a credential. An app-specific PIN would mean inventing a
/// place to keep it, a hash to compare it against, and a reset path when it is
/// forgotten — three new ways to leak or lock out a user, in exchange for a
/// secret no stronger than the one iOS already enforces.
///
/// The lock is a privacy screen over voice notes, not a vault: the transcripts
/// and audio on disk are protected by iOS file-level encryption, not by this.
/// Anyone stating otherwise to a user would be overselling it.
@MainActor
public final class AppLock: ObservableObject {
    public static let shared = AppLock()

    private static let enabledKey = "UnliRiceCapture_appLockEnabled"

    /// Whether the gate is switched on at all.
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            // Turning it on should not leave the app sitting unlocked behind the
            // switch that was just flipped; turning it off must not strand the
            // user behind a gate they just disabled.
            isLocked = isEnabled
            // A fresh choice deserves a fresh slate — otherwise the "no passcode
            // set" warning from a previous attempt sits under a switch that is
            // now working fine.
            if !isEnabled { lastError = nil }
        }
    }

    /// Whether the content is currently hidden.
    @Published public private(set) var isLocked: Bool

    @Published public private(set) var lastError: String?

    /// What the device can actually do, for labelling the setting honestly —
    /// offering "Face ID" on a device with no Face ID is a lie in the UI.
    public var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// False when the device has no passcode set at all. Enabling a lock there
    /// would gate the app behind an authentication that can never succeed.
    public var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    /// Re-locks when the app leaves the foreground.
    ///
    /// Locking on background rather than only on launch is the point — an app
    /// that only checks at launch is unlocked for anyone who picks up a phone
    /// that is already awake with it in the app switcher.
    public func lockOnBackground() {
        guard isEnabled else { return }
        isLocked = true
    }

    public func unlock() async {
        guard isEnabled, isLocked else { return }

        let context = LAContext()
        context.localizedFallbackTitle = ""

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // No passcode on the device: there is nothing to authenticate
            // against. Staying locked would make the app permanently unusable,
            // so the gate opens and says why rather than trapping the user.
            lastError = "This iPhone has no passcode set, so there is nothing to unlock with. Set one in Settings to use the lock."
            isLocked = false
            isEnabled = false
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your captures"
            )
            if ok {
                isLocked = false
                lastError = nil
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            // Cancelling is not a failure worth shouting about; the gate simply
            // stays shut and the unlock button is still there.
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
