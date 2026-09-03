import AppKit
import UnliRiceCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

@main
struct UnliRiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppStore()

    init() {
        // Counts this launch so the rating prompt can honour "never in the first
        // session". Records nothing else and shows nothing — see AppStore+Rating.
        AppStore.markReviewSessionStart()
    }

    var body: some Scene {
        WindowGroup("Unli Rice") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, idealWidth: 1080, minHeight: 600, idealHeight: 720)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .task {
                    while !Task.isCancelled {
                        await store.tickRoutines()
                        try? await Task.sleep(for: .seconds(300))
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                ) { _ in
                    store.flushHouseRulesState()
                }
        }
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

        Settings {
            PrivacyPolicyView()
        }
    }
}
