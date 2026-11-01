import SwiftUI
import UnliRiceCore

enum CaptureStudioStyle {
    static func color(_ token: StudioPalette.Token, _ scheme: ColorScheme) -> Color {
        let hex = StudioPalette.hex(token, scheme == .dark ? .dark : .light)
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct StudioDeck<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let symbol: String
    let accent: StudioPalette.Token
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
                .foregroundStyle(CaptureStudioStyle.color(accent, scheme))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(CaptureStudioStyle.color(.surface, scheme), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct StudioControl: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency { Capsule().fill(Theme.solidFill) }
                else { Capsule().fill(.thinMaterial) }
            }
            .overlay(Capsule().strokeBorder(Theme.borderLight, lineWidth: 1))
    }
}
extension View {
    func studioControl() -> some View { modifier(StudioControl()) }
}

struct CapturePrivacyCover: ViewModifier {
    @ObservedObject private var lock = AppLock.shared
    func body(content: Content) -> some View {
        ZStack {
            content.accessibilityHidden(lock.isLocked)
            if lock.isLocked {
                ZStack {
                    Theme.bgMain.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill").font(.largeTitle)
                        Text("Unli Rice is locked").font(.headline)
                        if let error = lock.lastError { Text(error).foregroundStyle(Theme.crit) }
                        Button("Unlock with \(lock.biometryLabel)") { Task { await lock.unlock() } }
                            .frame(minHeight: 44)
                    }.padding()
                }
                .zIndex(1)
            }
        }
    }
}
