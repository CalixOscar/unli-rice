import SwiftUI
import UIKit

@MainActor
final class CapturePresentation: ObservableObject {
    enum Mode { case awaiting, ordinary, closed, open }
    @Published var mode: Mode
    private(set) var hasSeenHinge = false
    init(mode: Mode = .awaiting) { self.mode = mode; hasSeenHinge = mode == .closed || mode == .open }
    var voiceOnly: Bool { mode == .awaiting || mode == .closed }
    func detached() { mode = hasSeenHinge ? .closed : .awaiting }

    func completeRegistration() {
        if mode == .awaiting && !hasSeenHinge { mode = .ordinary }
    }

    @available(iOS 27.1, *)
    func update(_ hinge: UIHinge?, window: UIWindow) {
        // Nil is not evidence of an ordinary device during initial registration.
        guard let hinge else { if hasSeenHinge { mode = .closed }; return }
        hasSeenHinge = true
        switch hinge.status {
        case .partiallyOpen, .fullyOpen: mode = .open
        default: mode = .closed; window.endEditing(true)
        }
    }
}

struct CaptureHingeObserver: UIViewRepresentable {
    @ObservedObject var presentation: CapturePresentation
    func makeUIView(context: Context) -> ObserverView { ObserverView(presentation: presentation) }
    func updateUIView(_ view: ObserverView, context: Context) {}
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.invalidate() }

    final class ObserverView: UIView {
        let presentation: CapturePresentation
        private var generation = UUID()
        private weak var attachedWindow: UIWindow?
        private var sawHingeInAttachment = false
        private var registrationObserver: CFRunLoopObserver?
        private var activationObserver: NSObjectProtocol?
        private var visibilityObserver: NSObjectProtocol?

        init(presentation: CapturePresentation) {
            self.presentation = presentation
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow !== window {
                if presentation.hasSeenHinge { window?.endEditing(true) }
                invalidate()
            }
            super.willMove(toWindow: newWindow)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            attachedWindow = window
            let current = UUID()
            generation = current
            sawHingeInAttachment = false
            if #available(iOS 27.1, *) {
                let interaction = UIHingeInteraction { [weak self, weak window] interaction, update in
                    guard let self, let window, self.generation == current,
                          self.attachedWindow === window, interaction.view === self,
                          self.window === window, interaction.isEnabled else { return }
                    let hinge = update.hinge
                    if hinge != nil { self.sawHingeInAttachment = true }
                    DispatchQueue.main.async { [weak self, weak window, weak interaction] in
                        guard let self, let window, let interaction, self.generation == current,
                              self.attachedWindow === window, interaction.view === self,
                              self.window === window, interaction.isEnabled else { return }
                        self.presentation.update(hinge, window: window)
                    }
                }
                interaction.isEnabled = false
                addInteraction(interaction)
                interaction.isEnabled = true
                activationObserver = NotificationCenter.default.addObserver(
                    forName: UIScene.didActivateNotification, object: window.windowScene, queue: .main
                ) { [weak self, weak window, weak interaction] _ in
                    guard let self, let window, let interaction else { return }
                    self.scheduleRegistrationCompletion(interaction, window: window, generation: current)
                }
                visibilityObserver = NotificationCenter.default.addObserver(
                    forName: UIWindow.didBecomeVisibleNotification, object: window, queue: .main
                ) { [weak self, weak window, weak interaction] _ in
                    guard let self, let window, let interaction else { return }
                    self.scheduleRegistrationCompletion(interaction, window: window, generation: current)
                }
                scheduleRegistrationCompletion(interaction, window: window, generation: current)
            } else { presentation.completeRegistration() }
        }

        @available(iOS 27.1, *)
        private func scheduleRegistrationCompletion(_ interaction: UIHingeInteraction, window: UIWindow, generation current: UUID) {
            guard generation == current, attachedWindow === window, self.window === window,
                  interaction.view === self, interaction.isEnabled else { return }
            if let registrationObserver { CFRunLoopObserverInvalidate(registrationObserver) }
            // Ordinary devices need not emit a nil update. Keep the initial cover
            // through UIKit's attachment cycle rather than guessing from a timer.
            registrationObserver = CFRunLoopObserverCreateWithHandler(
                nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
            ) { [weak self, weak window, weak interaction] _, _ in
                DispatchQueue.main.async { [weak self, weak window, weak interaction] in
                    guard let self, let window, let interaction, self.generation == current,
                          self.attachedWindow === window, self.window === window,
                          interaction.view === self, interaction.isEnabled,
                          !window.isHidden, window.windowScene?.activationState == .foregroundActive,
                          !self.sawHingeInAttachment else { return }
                    self.presentation.completeRegistration()
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), registrationObserver, .commonModes)
        }

        func invalidate() {
            generation = UUID()
            attachedWindow = nil
            sawHingeInAttachment = false
            if let registrationObserver { CFRunLoopObserverInvalidate(registrationObserver) }
            registrationObserver = nil
            if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
            activationObserver = nil
            if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
            visibilityObserver = nil
            if #available(iOS 27.1, *) {
                for interaction in interactions where interaction is UIHingeInteraction { removeInteraction(interaction) }
            }
            presentation.detached()
        }
    }
}
