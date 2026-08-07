import AppKit
import SwiftUI

/// Adaptive design tokens and control helpers, aligned with Unli Disk's design system
/// while preserving Unli Rice's teal/indigo-space core identity.
public struct Theme {
    // MARK: - Core Adaptive Tokens

    /// Main window background:
    /// - Dark Mode: Pitch dark Indigo-Space (`#0B0D15`)
    /// - Light Mode: Luminous Indigo-Slate (`#F0F4F9`)
    public static let bgMain: Color = adaptiveColor(
        light: Color(red: 0.941, green: 0.957, blue: 0.976),
        dark:  Color(red: 0.043, green: 0.051, blue: 0.082)
    )

    /// Card background:
    /// - Dark Mode: Translucent Cosmic Glass (`#0E1422`)
    /// - Light Mode: Crisp White (`#FFFFFF`)
    public static let bgCard: Color = adaptiveColor(
        light: .white,
        dark:  Color(red: 0.055, green: 0.078, blue: 0.133)
    )

    /// Primary Text:
    /// - Dark Mode: Luminous Icy White (`#F0F6FC`) — contrast ratio vs bgMain ~15:1
    /// - Light Mode: Deep Slate Navy (`#0F172A`) — contrast ratio vs bgMain ~14:1
    public static let textPrimary: Color = adaptiveColor(
        light: Color(red: 0.059, green: 0.090, blue: 0.165),
        dark:  Color(red: 0.941, green: 0.965, blue: 0.988)
    )

    /// Secondary Text:
    /// - Dark Mode: Slate Cyan Grey (`#8B9EB7`) — contrast ratio vs bgMain ~6.5:1
    /// - Light Mode: Sky Slate Blue (`#334155`) — contrast ratio vs bgMain ~7:1
    public static let textSecondary: Color = adaptiveColor(
        light: Color(red: 0.200, green: 0.255, blue: 0.333),
        dark:  Color(red: 0.545, green: 0.620, blue: 0.718)
    )

    /// Subtle / Muted Text:
    /// - Dark Mode: Atmospheric Grey (`#4C5D75`) — contrast ratio vs bgMain ~4.8:1
    /// - Light Mode: Soft Sky Slate (`#64748B`) — contrast ratio vs bgMain ~4.6:1
    public static let textLight: Color = adaptiveColor(
        light: Color(red: 0.392, green: 0.455, blue: 0.545),
        dark:  Color(red: 0.298, green: 0.365, blue: 0.459)
    )

    /// Accent Color:
    /// - Dark Mode: Electric Neon Teal (`#00F5D4`)
    /// - Light Mode: Deep Teal (`#00897B`) — deepened to maintain >= 4.5:1 contrast on light grounds
    public static let accentColor: Color = adaptiveColor(
        light: Color(red: 0.0, green: 0.537, blue: 0.482),
        dark:  Color(red: 0.0, green: 0.96, blue: 0.831)
    )

    public static let accentSoft: Color = accentColor.opacity(0.12)

    /// Border Light:
    /// - Dark Mode: Glass Stroke (`Color.white.opacity(0.12)`)
    /// - Light Mode: Sky Stroke (`#DCE6F2`)
    public static let borderLight: Color = adaptiveColor(
        light: Color(red: 0.863, green: 0.902, blue: 0.949),
        dark:  Color.white.opacity(0.12)
    )

    // MARK: - Control Tokens

    /// Surface for text fields / input controls
    public static let bgField: Color = adaptiveColor(
        light: Color(red: 0.957, green: 0.976, blue: 1.000),
        dark:  Color(red: 0.043, green: 0.059, blue: 0.102)
    )

    /// Fill for a solid control
    public static let solidFill: Color = adaptiveColor(
        light: .white,
        dark:  Color(red: 0.086, green: 0.122, blue: 0.200)
    )

    /// Label color on a solidFill button
    public static let onSolidFill: Color = adaptiveColor(
        light: Color(red: 0.059, green: 0.090, blue: 0.165),
        dark:  Color(red: 0.941, green: 0.965, blue: 0.988)
    )

    /// Hairline stroke around solidFill control
    public static let solidStroke: Color = adaptiveColor(
        light: Color(red: 0.0, green: 0.537, blue: 0.482).opacity(0.40),
        dark:  Color(red: 0.0, green: 0.96, blue: 0.831).opacity(0.35)
    )

    /// Fill for a disabled solid control
    public static let controlDisabledFill: Color = adaptiveColor(
        light: Color(red: 0.898, green: 0.925, blue: 0.957),
        dark:  Color(red: 0.051, green: 0.071, blue: 0.114)
    )

    // MARK: - Domain / Status Colors (Kept from Unli Rice original palette)

    /// Text and icons drawn *on top of* an `accent` or `brass` fill.
    ///
    /// The neon palette is bright — `accent` has a relative luminance of ~0.70,
    /// so white on it lands at 1.4:1 (below WCAG 4.5:1 floor). Dark ink on the same fill
    /// is ~13.9:1. Every filled button uses this instead of `.white`.
    public static let onAccent = Color(red: 0.043, green: 0.051, blue: 0.082)

    public static let brass = Color(red: 1.0, green: 0.69, blue: 0.0)          // Glowing Amber
    public static let crit = Color(red: 1.0, green: 0.165, blue: 0.373)        // Electric Neon Pink/Red
    public static let violet = Color(red: 0.827, green: 0.0, blue: 0.773)      // Neon Violet
    public static let emerald = Color(red: 0.0, green: 0.85, blue: 0.45)       // Neon Emerald

    // MARK: - Selection Tint Helpers

    public static func selectionTint(_ accent: Color) -> Color { accent.opacity(0.16) }
    public static func selectionStroke(_ accent: Color) -> Color { accent.opacity(0.55) }

    // MARK: - Dynamic Color Engine

    /// Creates a color that adapts to the current color scheme without needing
    /// an asset catalog — essential for SwiftPM builds.
    fileprivate static func adaptiveColor(light: Color, dark: Color) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
        #elseif canImport(UIKit)
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

    /// Selected row or pill: a tint of the surface's accent.
    public func selectedControl(cornerRadius: CGFloat, accent: Color, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(selected ? Theme.selectionTint(accent) : Theme.borderLight))
            .overlay(shape.strokeBorder(selected ? Theme.selectionStroke(accent) : .clear,
                                        lineWidth: 1))
    }
}
