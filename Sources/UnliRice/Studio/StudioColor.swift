import SwiftUI
import UnliRiceCore

extension Color {
    init(studio token: StudioPalette.Token, scheme: ColorScheme) {
        let value = StudioPalette.hex(token, scheme == .dark ? .dark : .light)
        let hex = String(value.dropFirst())
        let red = Double(Int(hex.prefix(2), radix: 16) ?? 0) / 255
        let green = Double(Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255
        let blue = Double(Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0) / 255
        self.init(.sRGB, red: red, green: green, blue: blue)
    }
}
