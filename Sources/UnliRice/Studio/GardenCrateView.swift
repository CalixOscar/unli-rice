import SwiftUI

struct GardenCrateView: View {
    let compact: Bool
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.studioGardenState {
            case .loading:
                ProgressView("Reading your garden…")
            case .failed(let message):
                Text(message).foregroundStyle(Theme.textSecondary)
            case .loaded:
                if store.studioSleeves.isEmpty {
                    Link(destination: URL(string: "https://www.calmdownoscar.com/idea-clinic/")!) {
                        Label("Plant your first idea", systemImage: "plus.circle")
                    }
                    .font(.system(size: 16, weight: .semibold))
                } else {
                    Text("\(store.studioSleeves.count) projects")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let sleeve = store.studioFrontSleeve {
                        Text(sleeve.name)
                            .font(.system(size: compact ? 16 : 20, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(sleeve.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
