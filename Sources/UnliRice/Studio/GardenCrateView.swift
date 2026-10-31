import SwiftUI
import UnliRiceCore

struct GardenCrateView: View {
    let compact: Bool
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var side: CGFloat { compact ? 200 : 340 }
    private let peek: CGFloat = 78

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.studioGardenState {
            case .loading:
                ProgressView("Reading your garden…")
            case .failed(let message):
                Text(message).foregroundStyle(Theme.textSecondary)
            case .loaded:
                if store.studioSleeves.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if compact {
                            Text(store.studioSleeves.count == 1 ? "1 project" : "\(store.studioSleeves.count) projects")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        crate
                        controls
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var crate: some View {
        let front = store.studioFrontIndex
        let last = store.studioSleeves.count - 1
        let first = reduceMotion ? front : max(front - 1, 0)
        let indices = Array(first...min(front + 3, last))
        return ZStack(alignment: .bottom) {
            ForEach(indices, id: \.self) { index in
                let sleeve = store.studioSleeves[index]
                let distance = index - front
                SleeveFront(sleeve: sleeve, side: side)
                    .modifier(SleeveMotion(distance: distance, reduceMotion: reduceMotion))
                    .zIndex(distance == -1 ? 1 : distance == 0 ? 0 : -Double(distance))
                    .allowsHitTesting(distance != -1)
                    .onTapGesture { if distance > 0 { select(index) } }
                    .accessibilityAddTraits(distance > 0 ? .isButton : [])
            }
        }
        .frame(width: side, height: side + peek, alignment: .bottom)
        .background(TrackpadSwipeCatcher { move(by: $0) })
        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            move(by: value.translation.width < 0 ? 1 : -1)
        })
        .modifier(ReduceMotionCrate(index: store.studioFrontIndex, reduceMotion: reduceMotion))
    }

    private var controls: some View {
        let front = store.studioFrontIndex
        let count = store.studioSleeves.count
        return HStack(spacing: 12) {
            Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityLabel("Previous project")
                .disabled(front == 0)
                .buttonStyle(.plain)
                .padding(8)
                .liquidGlassCapsule(interactive: true)
            if count <= 20 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(index == front ? Theme.textPrimary : Theme.textSecondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(front + 1) of \(count)")
            } else {
                Text("\(front + 1) of \(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(front + 1) of \(count)")
            }
            Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityLabel("Next project")
                .disabled(front == count - 1)
                .buttonStyle(.plain)
                .padding(8)
                .liquidGlassCapsule(interactive: true)
        }
    }

    private var emptyState: some View {
        let sleeve = RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Theme.textSecondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(width: side, height: side)
        let action = Link(destination: URL(string: "https://www.calmdownoscar.com/idea-clinic/")!) {
            Label("Plant your first idea", systemImage: "plus.circle")
        }
        .font(.system(size: 16, weight: .semibold))
        let pick = Button("Pick a folder") { store.chooseScanRoot() }
        return Group {
            if compact {
                VStack(alignment: .leading, spacing: 12) { sleeve.overlay(action); pick }
            } else {
                HStack(spacing: 16) { sleeve.overlay(action); pick }
            }
        }
    }

    private func move(by delta: Int) { select(store.studioFrontIndex + delta) }

    private func select(_ index: Int) {
        let target = min(max(index, 0), store.studioSleeves.count - 1)
        guard target != store.studioFrontIndex else { return }
        FlipSound.play()
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.78)
        withAnimation(animation) { store.studioFrontIndex = target }
    }
}

private struct SleeveMotion: ViewModifier {
    let distance: Int
    let reduceMotion: Bool

    // One unconditional chain, so a sleeve keeps its identity as it changes
    // place and the spring animates the change instead of crossfading.
    func body(content: Content) -> some View {
        let behind = max(distance, 0)
        content
            .rotation3DEffect(.degrees(distance == -1 && !reduceMotion ? -84 : 0),
                              axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
            .scaleEffect(1 - 0.06 * Double(behind))
            .offset(y: -26 * CGFloat(behind))
            .opacity(distance == -1 ? 0 : 1)
    }
}

private struct ReduceMotionCrate: ViewModifier {
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion { content.id(index).transition(.opacity) } else { content }
    }
}

private struct SleeveFront: View {
    let sleeve: GardenCrate.Sleeve
    let side: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var cover: StudioPalette.Token {
        [.cover0, .cover1, .cover2, .cover3, .cover4, .cover5, .cover6, .cover7][sleeve.coverIndex]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(studio: cover, scheme: colorScheme))
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .overlay {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Spacer(minLength: 0); sticker }
                    Spacer(minLength: 0)
                    Text(sleeve.name)
                        .font(.system(size: side > 200 ? 24 : 17, weight: .semibold))
                        .foregroundStyle(Color(studio: .coverText, scheme: colorScheme))
                        .lineLimit(2).truncationMode(.tail)
                    Text(sleeve.subtitle)
                        .font(.system(size: side > 200 ? 14 : 12))
                        .foregroundStyle(Color(studio: .coverSubtext, scheme: colorScheme))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            }
            .help(sleeve.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(sleeve.name), \(GardenCrateView.sticker(for: sleeve.state))")
    }

    private var sticker: some View {
        let text: String
        let fill: StudioPalette.Token
        let foreground: StudioPalette.Token
        switch sleeve.state {
        case .fine: text = "FINE"; fill = .stickerFineFill; foreground = .stickerDarkText
        case .needsYou: text = "NEEDS YOU"; fill = .stickerNeedsYouFill; foreground = .stickerDarkText
        case .noStatus: text = "NO NOTES YET"; fill = .stickerNoStatusFill; foreground = .stickerDarkText
        case .cantRead: text = "CAN'T READ"; fill = .stickerCantReadFill; foreground = .stickerLightText
        }
        return Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color(studio: fill, scheme: colorScheme)))
            .foregroundStyle(Color(studio: foreground, scheme: colorScheme))
            .modifier(StickerHelp(state: sleeve.state))
    }
}

private struct StickerHelp: ViewModifier {
    let state: GardenCrate.State

    func body(content: Content) -> some View {
        if case .cantRead(let reason) = state { content.help(reason) } else { content }
    }
}

extension GardenCrateView {
    static func sticker(for state: GardenCrate.State) -> String {
        switch state { case .fine: return "FINE"; case .needsYou: return "NEEDS YOU"; case .noStatus: return "NO NOTES YET"; case .cantRead: return "CAN'T READ" }
    }
}
