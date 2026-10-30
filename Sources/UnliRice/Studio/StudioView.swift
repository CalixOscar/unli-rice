import SwiftUI
import UnliRiceCore

struct StudioView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let sleeve = store.studioFrontSleeve {
                topStrip(for: sleeve)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
            GeometryReader { geo in
                ScrollView(.vertical) {
                    deckLayout(width: geo.size.width).padding(24)
                }
            }
        }
        .task(id: StudioLoadKey(dataPath: store.dataURL.path,
                                roots: store.scanRoots.map(\.path),
                                noteCount: store.notes.count)) {
            await store.refreshStudioGarden()
        }
        .task(id: store.studioFrontSleeve?.id) {
            await store.refreshStudioGate()
        }
    }

    @ViewBuilder
    private func deckLayout(width: CGFloat) -> some View {
        let garden = StudioDeck(title: "Garden", accent: .garden, shortcut: "1", expand: store.showGarden) {
            GardenCrateView(compact: true)
        }.frame(maxWidth: .infinity, alignment: .top)
        let branches = StudioDeck(title: "Branches", accent: .branches, shortcut: "2", expand: store.showRepos) {
            BranchesDeck()
        }.frame(maxWidth: .infinity, alignment: .top)
        let notes = StudioDeck(title: "Notes", accent: .notes, shortcut: "3", expand: store.showAllNotes) {
            NotesDeck()
        }.frame(maxWidth: .infinity, alignment: .top)

        if width >= 1080 {
            HStack(alignment: .top, spacing: 20) { garden; branches; notes }
        } else {
            VStack(spacing: 20) {
                garden
                HStack(alignment: .top, spacing: 20) { branches; notes }
            }
        }
    }

    private func topStrip(for sleeve: GardenCrate.Sleeve) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(sleeve.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(BuildGateLights.nextStep(store.studioFrontGate))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            BuildGateLights(result: store.studioFrontGate, showsLabels: true)
            Text("Lights show which files exist in this repo.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct StudioLoadKey: Equatable {
    let dataPath: String
    let roots: [String]
    let noteCount: Int
}
