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
                // The routine heartbeat. Coarse on purpose: the scheduler asks
                // "has this slot passed unserved", not "is it exactly 09:00", so
                // a late tick serves a slot just as well as a punctual one —
                // which is what lets a routine survive the Mac being asleep at
                // the scheduled minute. `tickRoutines` returns immediately
                // unless the user has turned routines on.
                .task {
                    while !Task.isCancelled {
                        await store.tickRoutines()
                        try? await Task.sleep(for: .seconds(300))
                    }
                }
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
