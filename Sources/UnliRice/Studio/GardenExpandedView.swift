import SwiftUI
import UnliRiceCore

struct GardenExpandedView: View {
    @EnvironmentObject var store: AppStore
    @State private var showsList = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Projects")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { Task { await store.refreshStudioGarden() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .liquidGlassCapsule(interactive: true)
                Picker("View", selection: $showsList) {
                    Text("Crate").tag(false)
                    Text("List").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            if showsList {
                ProjectGardenView()
            } else if let front = store.studioFrontSleeve {
                HStack(alignment: .top, spacing: 32) {
                    GardenCrateView(compact: false)
                    ScrollView(.vertical) {
                        SleeveBackView(sleeve: front, result: store.studioFrontGate)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                GardenCrateView(compact: false)
            }
        }
        .padding(24)
        .background(Color(studio: .background, scheme: colorScheme))
        .task {
            if store.studioGardenState == .loading { await store.refreshStudioGarden() }
        }
        .task(id: StudioGateKey(sleeveID: store.studioFrontSleeve?.id, refresh: store.studioRefreshCount)) { await store.refreshStudioGate() }
    }
}
