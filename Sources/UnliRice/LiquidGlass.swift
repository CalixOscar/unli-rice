import SwiftUI

/// Liquid Glass, with an honest fallback.
///
/// `.glassEffect` is macOS 26+ and this app still deploys to macOS 14 (see `Package.swift`),
/// so every call site goes through here rather than scattering `#available` checks across
/// the view layer. On Tahoe you get the real system material — lensing, specular edge,
/// interactive deformation. Below it you get `.ultraThinMaterial` plus a hairline stroke,
/// which reads as frosted glass without pretending to be the system effect.
///
/// Raising the deployment target to macOS 26 would let all of this collapse to a direct
/// `.glassEffect` call; that is a distribution decision, not a styling one.
extension View {
    /// - Parameters:
    ///   - cornerRadius: corner radius of the glass shape.
    ///   - tint: optional colour pushed through the material. Keep it low-saturation —
    ///     glass tints multiply against whatever is behind them.
    ///   - interactive: on macOS 26, makes the glass deform and highlight under the
    ///     pointer. Use only on things that are actually hit-testable.
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// Capsule-shaped variant, for pills and sliders.
    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: nil, tint: tint, interactive: interactive))
    }
}

struct LiquidGlassBackground: ViewModifier {
    /// `nil` means capsule.
    let cornerRadius: CGFloat?
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            modern(content)
        } else {
            legacy(content)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func modern(_ content: Content) -> some View {
        if let cornerRadius {
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.glassEffect(glass, in: .capsule)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        var result = Glass.regular
        if let tint {
            result = result.tint(tint)
        }
        if interactive {
            result = result.interactive()
        }
        return result
    }

    private func legacy(_ content: Content) -> some View {
        let shape: AnyShape = cornerRadius
            .map { AnyShape(RoundedRectangle(cornerRadius: $0, style: .continuous)) }
            ?? AnyShape(Capsule())
        // A tinted material is two stacked fills below macOS 26 — there is no single
        // style that both blurs and tints the way `Glass.tint` does.
        return content
            .background(.ultraThinMaterial, in: shape)
            .background((tint ?? .clear).opacity(tint == nil ? 0 : 0.18), in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}
