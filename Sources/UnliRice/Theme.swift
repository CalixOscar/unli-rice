import AppKit
import SwiftUI

/// Warm-paper/ledger palette carried over from the product-strategy mock, adapted
/// for light/dark via NSColor's dynamic provider since this target has no asset catalog.
enum Theme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.082) // Pitch dark Indigo-Space
    static let panel = Color.black.opacity(0.35)                        // Translucent glass backing
    static let border = Color.white.opacity(0.12)                       // Silver frosted glass border
    static let ink = Color.white                                        // Crisp white ink
    static let inkDim = Color(red: 0.627, green: 0.659, blue: 0.753)    // Muted silver text
    static let accent = Color(red: 0.0, green: 0.96, blue: 0.831)       // Electric Neon Teal
    static let accentSoft = Color(red: 0.0, green: 0.96, blue: 0.831).opacity(0.12)
    static let brass = Color(red: 1.0, green: 0.69, blue: 0.0)          // Glowing Amber
    static let crit = Color(red: 1.0, green: 0.165, blue: 0.373)        // Electric Neon Pink/Red
    static let violet = Color(red: 0.827, green: 0.0, blue: 0.773)      // Neon Violet
    static let emerald = Color(red: 0.0, green: 0.85, blue: 0.45)       // Neon Emerald
}
