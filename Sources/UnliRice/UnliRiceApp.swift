import AppKit
import UnliRiceCore
import SwiftUI

@main
struct UnliRiceApp: App {
    @StateObject private var store = AppStore()

    init() {
        // A bare `swift run` executable has no app bundle, so LaunchServices
        // never tells AppKit this is a foreground GUI app — without this, the
        // window is created but never brought forward or made key.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Unli Rice") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .saveItem) {
                Menu("Export Notes") {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button("as \(format.displayName)…") {
                            store.exportNotes(as: format)
                        }
                    }
                }
            }
        }
    }
}
