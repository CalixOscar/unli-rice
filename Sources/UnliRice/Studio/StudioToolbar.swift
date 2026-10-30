import AppKit
import SwiftUI

struct StudioToolbar: View {
    @EnvironmentObject var store: AppStore
    @State private var showingCapture = false

    var body: some View {
        HStack {
            if store.pane != .studio && store.pane != .guardrailsGrounding && store.pane != .firstRun && store.selectedNoteID == nil {
                Button {
                    store.lastTab == .studio ? store.showStudio() : store.showGuardrailsGrounding()
                } label: {
                    Label("All decks", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)
                .liquidGlassCapsule(interactive: true)
                .frame(width: 110, alignment: .leading)
            } else {
                Color.clear.frame(width: 110)
            }
            Spacer()
            tabs
            Spacer()
            gear
        }
        .frame(height: 52)
        .padding(.horizontal, 16)
        .background(Theme.bgMain)
        .sheet(isPresented: $showingCapture) {
            CapturePromoSheet().environmentObject(store)
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tab("Studio", selected: store.lastTab == .studio) {
                store.showStudio()
            }
            .keyboardShortcut("1", modifiers: .command)

            tab("Guardrails & Grounding", selected: store.lastTab == .guardrailsGrounding) {
                store.showGuardrailsGrounding()
            }
            .keyboardShortcut("2", modifiers: .command)
        }
        .padding(4)
        .liquidGlassCapsule()
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule().fill(Theme.accentSoft)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var gear: some View {
        Menu {
            Button("Setup") {
                store.selectNote(nil)
                store.showSetup()
            }
            Button("Trust Center") { store.showTrustCenter() }
            Button("Archived notes") { store.showArchived() }

            Divider()

            if store.isOn(.todo) {
                Button("To do") { store.showTodo() }
            }
            if store.isOn(.map) {
                Button("Map") { store.showGraph() }
            }
            if store.isOn(.yearSoFar) {
                Button("Your year so far") { store.showRetrospective() }
            }
            if store.isOn(.capturePromo) {
                Button("iPhone Capture") { showingCapture = true }
            }

            Divider()

            Button("Rate Unli Rice") {
                NSWorkspace.shared.open(AppStore.writeReviewURL)
            }
        } label: {
            Image(systemName: "gearshape")
                .frame(width: 44, height: 44)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .liquidGlassCapsule(interactive: true)
        .accessibilityLabel("Settings and more")
    }
}
