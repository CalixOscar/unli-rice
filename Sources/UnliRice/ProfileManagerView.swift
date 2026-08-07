import UnliRiceCore
import SwiftUI

/// Profile Manager pane for managing multi-vault profiles, switching active profile,
/// and designating the Master Profile.
struct ProfileManagerView: View {
    @EnvironmentObject var store: AppStore
    @State private var newProfileName: String = ""
    @State private var newProfileFolder: String = ""
    @State private var copyMasterGuardrails: Bool = true
    @State private var showCreateSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profiles")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                    Text("One profile = one vault folder. Switching profiles reopens memory against that vault.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                Button("+ New Profile") {
                    showCreateSheet = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.onAccent)
                .background(Theme.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Profile List
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.profileRegistry.profiles) { profile in
                        let isActive = profile.id == store.profileRegistry.activeProfileID
                        
                        HStack(spacing: 12) {
                            Circle()
                                .fill(isActive ? Theme.accentColor : Theme.textSecondary.opacity(0.4))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(profile.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)

                                    if profile.isMaster {
                                        Text("MASTER")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .foregroundStyle(Theme.brass)
                                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.brass, lineWidth: 1))
                                    }

                                    if isActive {
                                        Text("ACTIVE")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .foregroundStyle(Theme.accentColor)
                                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.accentColor, lineWidth: 1))
                                    }
                                }

                                Text(profile.folderPath)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if !isActive {
                                Button("Switch") {
                                    store.switchProfile(profile)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .foregroundStyle(Theme.accentColor)
                                .solidControl(cornerRadius: 4)
                            }

                            if !profile.isMaster {
                                Button("Set as Master") {
                                    store.profileRegistry.setMasterProfile(id: profile.id)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(12)
                        .liquidGlass(cornerRadius: 6)
                    }
                }
            }

            // Create New Profile Modal/Inline Section
            if showCreateSheet {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Create New Profile Vault")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.brass)

                    TextField("Profile Name (e.g. Work, Side Project)", text: $newProfileName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(7)
                        .background(Theme.bgField)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))

                    HStack {
                        TextField("Vault Directory Path", text: $newProfileFolder)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(7)
                            .background(Theme.bgField)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))

                        Button("Choose Folder…") {
                            chooseFolder()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.onSolidFill)
                        .solidControl(cornerRadius: 4)
                    }

                    Toggle("Snapshot copy Master Profile guardrails into new vault", isOn: $copyMasterGuardrails)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    HStack {
                        Button("Cancel") {
                            showCreateSheet = false
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)

                        Spacer()

                        Button("Create Profile") {
                            createProfile()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .disabled(newProfileName.isEmpty || newProfileFolder.isEmpty)
                    }
                }
                .padding(14)
                .liquidGlass(cornerRadius: 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            newProfileFolder = url.path
        }
    }

    private func createProfile() {
        guard !newProfileName.isEmpty, !newProfileFolder.isEmpty else { return }
        store.createNewProfile(name: newProfileName, folderPath: newProfileFolder, copyMasterGuardrails: copyMasterGuardrails)
        newProfileName = ""
        newProfileFolder = ""
        showCreateSheet = false
    }
}
