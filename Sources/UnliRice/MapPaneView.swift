import SwiftUI
import UnliRiceCore

/// The map, with the one action that changes what's on it.
///
/// Lifted out of `MoreView` when Map became a sidebar destination: the pane is
/// the whole main column now, not a chip's worth of content under More's
/// horizontal selector bar.
struct MapPaneView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Map")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button(action: {
                    store.chooseScanRoot()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text("Index a folder")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(Theme.accentColor)
                    .solidControl(cornerRadius: 6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            NoteGraphView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
    }
}
