import UnliRiceCore
import SwiftUI

/// Unified Setup screen — answers "How do I wire it up?".
/// Merges Connectors, Profile & Vaults, House Rules, Mirror Export, and Automation.
struct SetupView: View {
    @EnvironmentObject var store: AppStore

    enum Tab: String, CaseIterable, Identifiable {
        case connect = "AI Tools"
        case folders = "Folders"
        case automation = "What runs on its own"
        case profiles = "Separate memories"

        var id: String { rawValue }
    }

    private var visibleTabs: [Tab] {
        Tab.allCases.filter { $0 != .profiles || store.profileRegistry.profiles.count > 1 }
    }

    private var effectiveTab: Tab {
        visibleTabs.contains(store.setupTab) ? store.setupTab : .connect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with tab bar
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Configure how AI tools connect, your personal profiles, and automation rules.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }

                // Tab Selector
                HStack(spacing: 6) {
                    ForEach(visibleTabs) { tab in
                        Button(action: { store.setupTab = tab }) {
                            Text(tab.rawValue)
                                .font(.system(size: 11.5, weight: effectiveTab == tab ? .bold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(effectiveTab == tab ? Theme.accentColor : Theme.textSecondary)
                                .selectedControl(cornerRadius: 6, accent: Theme.accentColor, selected: effectiveTab == tab)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .liquidGlass(cornerRadius: 0)

            Divider().opacity(0.2)

            // Selected Tab Content
            Group {
                switch effectiveTab {
                case .connect:
                    ConnectView()
                case .folders:
                    AutomationView()
                case .profiles:
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Button("Launch Profile Builder Wizard →") {
                                store.showProfileBuilder()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(Theme.onAccent)
                            .background(Theme.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(.leading, 20)
                            .padding(.top, 12)

                            Spacer()
                        }

                        ProfileManagerView()
                    }
                case .automation:
                    AutomationView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
    }
}
