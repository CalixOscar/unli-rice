import SwiftUI
import UnliRiceCore

struct CaptureProjectDeck: View {
    let projects: [StudioOverviewFile.Project]
    @Binding var selectedID: String?
    let notes: [Note]
    let sticker: (StudioOverviewFile.Project) -> String
    let todoCount: (StudioOverviewFile.Project) -> Int
    let open: (StudioOverviewFile.Project) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var width: CGFloat = 0

    private var front: Int { projects.firstIndex { $0.id == selectedID } ?? 0 }
    private var visibleIndices: [Int] {
        guard !projects.isEmpty else { return [] }
        return Array((reduceMotion ? front : max(front - 1, 0))...min(front + 3, projects.count - 1))
    }
    private var peek: CGFloat { min(78, width * 0.23) }
    private var side: CGFloat { max(1, width - peek) }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .leading) {
                ForEach(visibleIndices, id: \.self) { index in
                    let project = projects[index]
                    let distance = index - front
                    sleeve(project)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 40).exclusively(before: TapGesture()).onEnded { result in
                            switch result {
                            case .first(let value):
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                select(front + (value.translation.width < 0 ? 1 : -1))
                            case .second:
                                tap(project, index: index, distance: distance)
                            }
                        }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { tap(project, index: index, distance: distance) }
                    .scaleEffect(distance < 0 ? 0.94 : 1 - 0.06 * Double(distance))
                    .offset(x: distance < 0 ? -side * 0.6 : peek / 3 * CGFloat(distance))
                    .opacity(distance < 0 ? 0 : 1)
                    .zIndex(distance < 0 ? 1 : -Double(distance))
                    .allowsHitTesting(distance >= 0)
                    .accessibilityHidden(distance != 0)
                    .accessibilityIdentifier("studio-project-\(project.id)")
                    .accessibilityLabel("Open project \(project.name), \(sticker(project)), \(project.status ?? "Status unknown")")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: select(front + 1)
                case .decrement: select(front - 1)
                @unknown default: break
                }
            }
            .modifier(CaptureDeckReduceMotion(index: front, reduceMotion: reduceMotion))
            HStack {
                Button { select(front - 1) } label: {
                    Label("Previous project", systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.studioControl().disabled(front == 0)
                Spacer()
                Text("\(front + 1) of \(projects.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { select(front + 1) } label: {
                    Label("Next project", systemImage: "chevron.right").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }.studioControl().disabled(front + 1 == projects.count)
            }
        }
        .background(GeometryReader { geometry in
            Color.clear.onAppear { width = geometry.size.width }
                .onChange(of: geometry.size.width) { _, newWidth in width = newWidth }
        })
    }

    private func sleeve(_ project: StudioOverviewFile.Project) -> some View {
        let pending = CaptureContext.pendingNotes(in: notes, project: project.projectTag).count
        let todos = todoCount(project)
        let covers: [StudioPalette.Token] = [.cover0, .cover1, .cover2, .cover3, .cover4, .cover5, .cover6, .cover7]
        return VStack(alignment: .leading, spacing: 12) {
            HStack { Spacer(minLength: 0); Text(sticker(project)).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.18), in: Capsule()) }
            Spacer(minLength: 0)
            Image(systemName: "folder.fill").font(.title2).accessibilityHidden(true)
            Text(project.name).font(.title2.bold()).multilineTextAlignment(.leading)
            Text(project.status ?? "Status unknown").font(.subheadline).multilineTextAlignment(.leading)
            Text("\(pending) pending \(pending == 1 ? "capture" : "captures") · \(todos) \(todos == 1 ? "to-do" : "to-dos")").font(.caption).multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: side, alignment: .leading)
        .frame(minHeight: side, alignment: .topLeading)
        .background(CaptureStudioStyle.color(covers[GardenCrate.stableIndex(project.id, modulo: 8)], scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .contentShape(Rectangle())
    }

    private func tap(_ project: StudioOverviewFile.Project, index: Int, distance: Int) {
        if distance == 0 { open(project) } else if distance > 0 { select(index) }
    }

    private func select(_ index: Int) {
        guard !projects.isEmpty else { return }
        let target = min(max(index, 0), projects.count - 1)
        guard target != front else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.78)) {
            selectedID = projects[target].id
        }
    }
}

private struct CaptureDeckReduceMotion: ViewModifier {
    let index: Int
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        if reduceMotion { content.id(index).transition(.opacity) } else { content }
    }
}
