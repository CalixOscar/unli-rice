import AppKit
import SwiftUI

/// Warm-paper/ledger palette carried over from the product-strategy mock, adapted
/// for light/dark via NSColor's dynamic provider since this target has no asset catalog.
enum Theme {
    static let background = adaptive(light: (0.925, 0.933, 0.906), dark: (0.09, 0.106, 0.09))
    static let panel = adaptive(light: (0.969, 0.973, 0.949), dark: (0.122, 0.141, 0.122))
    static let border = adaptive(light: (0.788, 0.8, 0.753), dark: (0.2, 0.227, 0.184))
    static let ink = adaptive(light: (0.106, 0.129, 0.188), dark: (0.910, 0.906, 0.867))
    static let inkDim = adaptive(light: (0.337, 0.361, 0.322), dark: (0.635, 0.663, 0.608))
    static let accent = adaptive(light: (0.184, 0.420, 0.310), dark: (0.435, 0.745, 0.576))
    static let accentSoft = adaptive(light: (0.863, 0.906, 0.867), dark: (0.141, 0.208, 0.165))
    static let brass = adaptive(light: (0.659, 0.463, 0.227), dark: (0.827, 0.643, 0.361))
    static let crit = adaptive(light: (0.639, 0.259, 0.227), dark: (0.878, 0.514, 0.475))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}
