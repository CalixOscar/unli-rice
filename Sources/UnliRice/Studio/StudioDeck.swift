import SwiftUI
import UnliRiceCore

struct StudioDeck<Content: View>: View {
    let title: String
    let accent: StudioPalette.Token
    let shortcut: KeyEquivalent
    let expand: () -> Void
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(title: String, accent: StudioPalette.Token, shortcut: KeyEquivalent,
         expand: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.shortcut = shortcut
        self.expand = expand
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color(studio: accent, scheme: colorScheme))
                Spacer()
                Button(action: expand) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Open \(title)")
                .keyboardShortcut(shortcut, modifiers: [])
                .liquidGlassCapsule(interactive: true)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(studio: .surface, scheme: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
