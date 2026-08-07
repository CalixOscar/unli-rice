import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Adaptive design tokens and control helpers for Unli Rice Capture (iOS),
/// aligned with Unli Rice Mac and Unli Disk design system tokens.
public struct Theme {
    // MARK: - Core Adaptive Tokens

    /// Main window / view background:
    /// - Dark Mode: Dark Indigo/Slate Space (`#0B0E17`)
    /// - Light Mode: Luminous Indigo-Slate (`#F0F4F9`)
    public static let bgMain: Color = adaptiveColor(
        light: Color(red: 0.941, green: 0.957, blue: 0.976),
        dark:  Color(red: 0.043, green: 0.055, blue: 0.090)
    )

    /// Card background:
    /// - Dark Mode: Translucent Slate Glass (`#131722`)
    /// - Light Mode: Crisp White (`#FFFFFF`)
    public static let bgCard: Color = adaptiveColor(
        light: .white,
        dark:  Color(red: 0.075, green: 0.090, blue: 0.133)
    )

    /// Primary Text:
    /// - Dark Mode: Crisp Off-White (`#F8FAFC`) — contrast ratio vs bgMain ~15:1
    /// - Light Mode: Deep Slate Navy (`#0F172A`) — contrast ratio vs bgMain ~14:1
    public static let textPrimary: Color = adaptiveColor(
        light: Color(red: 0.059, green: 0.090, blue: 0.165),
        dark:  Color(red: 0.973, green: 0.980, blue: 0.988)
    )

    /// Secondary Text:
    /// - Dark Mode: Cool Slate (`#94A3B8`) — contrast ratio vs bgMain ~6.5:1
    /// - Light Mode: Sky Slate (`#475569`) — contrast ratio vs bgMain ~7:1
    public static let textSecondary: Color = adaptiveColor(
        light: Color(red: 0.278, green: 0.333, blue: 0.412),
        dark:  Color(red: 0.580, green: 0.639, blue: 0.722)
    )

    /// Subtle / Muted Text:
    /// - Dark Mode: Muted Slate (`#64748B`)
    /// - Light Mode: Soft Slate (`#64748B`)
    public static let textLight: Color = adaptiveColor(
        light: Color(red: 0.392, green: 0.455, blue: 0.545),
        dark:  Color(red: 0.392, green: 0.455, blue: 0.545)
    )

    /// Accent Color:
    /// - Dark Mode: Electric Cerulean Blue (`#0484FF`) — Unli Disk Signature Accent
    /// - Light Mode: Deep Cerulean Blue (`#0066CC`)
    public static let accentColor: Color = adaptiveColor(
        light: Color(red: 0.0, green: 0.40, blue: 0.80),
        dark:  Color(red: 0.04, green: 0.52, blue: 1.0)
    )

    public static let accentSoft: Color = accentColor.opacity(0.16)

    /// Border Light:
    /// - Dark Mode: Glass Stroke (`Color.white.opacity(0.10)`)
    /// - Light Mode: Sky Stroke (`#DCE6F2`)
    public static let borderLight: Color = adaptiveColor(
        light: Color(red: 0.863, green: 0.902, blue: 0.949),
        dark:  Color.white.opacity(0.10)
    )

    // MARK: - Control Tokens

    /// Surface for text fields / input controls
    public static let bgField: Color = adaptiveColor(
        light: Color(red: 0.957, green: 0.976, blue: 1.000),
        dark:  Color(red: 0.071, green: 0.086, blue: 0.125)
    )

    /// Fill for a solid control
    public static let solidFill: Color = adaptiveColor(
        light: .white,
        dark:  Color(red: 0.090, green: 0.110, blue: 0.157)
    )

    /// Label color on a solidFill button
    public static let onSolidFill: Color = adaptiveColor(
        light: Color(red: 0.059, green: 0.090, blue: 0.165),
        dark:  Color(red: 0.973, green: 0.980, blue: 0.988)
    )

    /// Hairline stroke around solidFill control
    public static let solidStroke: Color = adaptiveColor(
        light: Color(red: 0.820, green: 0.860, blue: 0.910),
        dark:  Color(red: 0.145, green: 0.180, blue: 0.251)
    )

    /// Fill for a disabled solid control
    public static let controlDisabledFill: Color = adaptiveColor(
        light: Color(red: 0.898, green: 0.925, blue: 0.957),
        dark:  Color(red: 0.051, green: 0.071, blue: 0.114)
    )

    // MARK: - Domain / Status Colors

    public static let onAccent = Color.white

    public static let brass = Color(red: 0.96, green: 0.62, blue: 0.14)        // Amber/Gold
    public static let crit = Color(red: 0.93, green: 0.27, blue: 0.36)         // Soft Crimson
    public static let violet = Color(red: 0.66, green: 0.33, blue: 0.97)       // Soft Violet
    public static let emerald = Color(red: 0.06, green: 0.73, blue: 0.50)      // Emerald Green

    // MARK: - Selection Tint Helpers

    public static func selectionTint(_ accent: Color) -> Color { accent.opacity(0.16) }
    public static func selectionStroke(_ accent: Color) -> Color { accent.opacity(0.55) }

    // MARK: - Dynamic Color Engine

    fileprivate static func adaptiveColor(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        return light
        #endif
    }
}

extension View {
    /// Primary solid control treatment: fill plus hairline stroke.
    public func solidControl(cornerRadius: CGFloat, enabled: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(enabled ? Theme.solidFill : Theme.controlDisabledFill))
            .overlay(shape.strokeBorder(enabled ? Theme.solidStroke : Theme.borderLight,
                                        lineWidth: 1))
    }

    /// Card container treatment: bgCard fill plus subtle border.
    public func cardStyle(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(Theme.bgCard))
            .overlay(shape.strokeBorder(Theme.borderLight, lineWidth: 1))
    }

    /// Selected control or pill treatment.
    public func selectedControl(cornerRadius: CGFloat, accent: Color = Theme.accentColor, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(selected ? Theme.selectionTint(accent) : Theme.bgCard))
            .overlay(shape.strokeBorder(selected ? Theme.selectionStroke(accent) : Theme.borderLight,
                                        lineWidth: 1))
    }
}
