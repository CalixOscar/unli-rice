import SwiftUI
import UIKit

@MainActor
final class CapturePresentation: ObservableObject {
    enum Mode { case awaiting, ordinary, closed, open }
    @Published var mode: Mode
    private(set) var hasSeenHinge = false
    init(mode: Mode = .awaiting) { self.mode = mode; hasSeenHinge = mode == .closed || mode == .open }
    var voiceOnly: Bool { mode == .awaiting || mode == .closed }
    func detached() { if hasSeenHinge { mode = .closed } else { mode = .awaiting } }
    @available(iOS 27.1, *)
    func update(_ hinge: UIHinge?, window: UIWindow) {
        guard let hinge else { mode = hasSeenHinge ? .closed : .ordinary; return }
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
        init(presentation: CapturePresentation) { self.presentation = presentation; super.init(frame: .zero); isUserInteractionEnabled = false }
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
            let current = UUID(); generation = current
            if #available(iOS 27.1, *) {
                let interaction = UIHingeInteraction { [weak self, weak window] interaction, update in
                    guard let self, let window, self.generation == current,
                          self.attachedWindow === window, interaction.view?.window === window else { return }
                    let hinge = update.hinge
                    DispatchQueue.main.async { [weak self, weak window, weak interaction] in
                        guard let self, let window, let interaction, self.generation == current,
                              self.attachedWindow === window, interaction.view?.window === window else { return }
                        self.presentation.update(hinge, window: window)
                    }
                }
                addInteraction(interaction)
            } else { presentation.mode = .ordinary }
        }
        func invalidate() {
            generation = UUID(); attachedWindow = nil
            if #available(iOS 27.1, *) {
                for interaction in interactions where interaction is UIHingeInteraction { removeInteraction(interaction) }
            }
            presentation.detached()
        }
    }
}
