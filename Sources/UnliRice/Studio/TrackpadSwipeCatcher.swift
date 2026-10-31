import AppKit
import SwiftUI
import UnliRiceCore

struct TrackpadSwipeCatcher: NSViewRepresentable {
    let onFlip: (Int) -> Void

    func makeNSView(context: Context) -> SwipeView { SwipeView(onFlip: onFlip) }
    func updateNSView(_ view: SwipeView, context: Context) { view.onFlip = onFlip }

    final class SwipeView: NSView {
        var onFlip: (Int) -> Void
        private var tracker = TrackpadSwipe()
        private var monitor: Any?

        init(onFlip: @escaping (Int) -> Void) {
            self.onFlip = onFlip
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let phase: TrackpadSwipe.Phase
                if !event.hasPreciseScrollingDeltas { phase = .other }
                else if !event.momentumPhase.isEmpty { phase = .momentum }
                else if event.phase.contains(.began) { phase = .began }
                else if event.phase.contains(.changed) { phase = .changed }
                else if event.phase.contains(.ended) || event.phase.contains(.cancelled) { phase = .ended }
                else { phase = .other }
                if phase == .began && !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.tracker = TrackpadSwipe()
                    return event
                }
                let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
                let result = self.tracker.handle(phase: phase, fingerDX: dx, dy: event.scrollingDeltaY)
                if let flip = result.flip { self.onFlip(flip) }
                return result.consume ? nil : event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
