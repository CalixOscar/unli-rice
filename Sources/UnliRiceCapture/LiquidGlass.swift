import SwiftUI

/// Liquid Glass for Capture.
///
/// Unlike `UnliRice/LiquidGlass.swift` on Mac — which still deploys to macOS 13
/// and has to fall back to `.ultraThinMaterial` below macOS 26 — Capture's
/// floor is already iOS 26 (see `Package.swift`, where `SpeechAnalyzer` set the
/// floor for an unrelated reason). `.glassEffect` and `Glass` are therefore
/// unconditionally available here; there is no legacy branch to write.
extension View {
    /// - Parameters:
    ///   - cornerRadius: corner radius of the glass shape.
    ///   - tint: optional colour pushed through the material. Keep it
    ///     low-saturation — glass tints multiply against whatever is behind them.
    ///     `Theme.accentColor` at its default opacity is the house tint.
    ///   - interactive: makes the glass deform and highlight under touch. Use
    ///     only on things that are actually hit-testable.
    func liquidGlass(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// Capsule-shaped variant, for pills and buttons.
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: nil, tint: tint, interactive: interactive))
    }
}

private struct LiquidGlassBackground: ViewModifier {
    /// `nil` means capsule.
    let cornerRadius: CGFloat?
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if let cornerRadius {
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.glassEffect(glass, in: .capsule)
        }
    }

    private var glass: Glass {
        var result = Glass.regular
        if let tint { result = result.tint(tint) }
        if interactive { result = result.interactive() }
        return result
    }
}
