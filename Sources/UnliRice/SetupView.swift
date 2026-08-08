import UnliRiceCore
import SwiftUI

/// Unified Setup screen — answers "How do I wire it up?".
/// Merges Connectors, Profile & Vaults, House Rules, Mirror Export, and Automation.
struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: Tab = .connect

    enum Tab: String, CaseIterable, Identifiable {
        case connect = "AI Tools"
        case profiles = "Separate memories"
        case houseRules = "What your AI should always do"
        case mirrorExport = "The folder your AI can read"
        case automation = "What Runs on Its Own"

        var id: String { rawValue }
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
                    ForEach(Tab.allCases) { tab in
                        Button(action: { selectedTab = tab }) {
                            Text(tab.rawValue)
                                .font(.system(size: 11.5, weight: selectedTab == tab ? .bold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(selectedTab == tab ? Theme.accentColor : Theme.textSecondary)
                                .selectedControl(cornerRadius: 6, accent: Theme.accentColor, selected: selectedTab == tab)
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
                switch selectedTab {
                case .connect:
                    ConnectView()
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
                case .houseRules:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("House Rules are standing instructions read by every connected assistant at session start.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)

                            HouseRulesPresetGalleryView {
                                store.reload()
                            }
                        }
                        .padding(20)
                    }
                case .mirrorExport:
                    MirrorExportView()
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
