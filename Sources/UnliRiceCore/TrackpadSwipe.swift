public struct TrackpadSwipe {
    public enum Phase: Equatable { case began, changed, ended, momentum, other }
    public static let threshold: Double = 50
    public static let decideAfter: Double = 4
    private enum Axis { case undecided, horizontal, vertical }
    private var active = false
    private var axis = Axis.undecided
    private var absX = 0.0, absY = 0.0, total = 0.0
    private var fired = false, lastWasHorizontal = false
    public init() {}

    public mutating func handle(phase: Phase, fingerDX: Double, dy: Double) -> (consume: Bool, flip: Int?) {
        switch phase {
        case .began:
            self = TrackpadSwipe()
            active = true
            return handle(phase: .changed, fingerDX: fingerDX, dy: dy)
        case .changed:
            guard active else { return (false, nil) }
            total += fingerDX
            absX += abs(fingerDX)
            absY += abs(dy)
            if axis == .undecided && absX + absY >= Self.decideAfter {
                axis = absX > absY ? .horizontal : .vertical
            }
            guard axis == .horizontal else { return (false, nil) }
            if !fired && abs(total) >= Self.threshold {
                fired = true
                return (true, total < 0 ? 1 : -1)
            }
            return (true, nil)
        case .ended:
            lastWasHorizontal = axis == .horizontal
            active = false
            axis = .undecided
            return (lastWasHorizontal, nil)
        case .momentum: return (lastWasHorizontal, nil)
        case .other: return (false, nil)
        }
    }
}
