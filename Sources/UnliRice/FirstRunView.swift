import SwiftUI
import UnliRiceCore

/// First-run view implementing State 1 (One question) and State 2 (Connected, waiting for first note).
struct FirstRunView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTool: ToolOption? = .claude

    enum ToolOption: String, CaseIterable, Identifiable {
        case claude = "Claude"
        case chatgpt = "ChatGPT"
        case cursor = "Cursor"
        case somethingElse = "Something else"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.hasUserAuthoredNotes {
                // State 3 transition fallback
                connectedState3View
            } else if let connectedClient = store.connectedClientName {
                // State 2: Connected, no notes yet
                state2ConnectedView(clientName: connectedClient)
            } else {
                // State 1: Nothing connected yet — the 1-question first run
                state1QuestionView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgMain)
        .safeAreaInset(edge: .bottom) { skipBar }
        .onAppear {
            store.refreshTrustCenter()
        }
    }

    /// A way out of first run, present in EVERY state.
    ///
    /// Both existing exits — "Continue to App" and "Go to Home" — live in the connected
    /// states, so the one screen a new user actually lands on had none: connecting an MCP
    /// client was the only route past it, short of quitting. Connecting is optional, and
    /// FirstRunView replaces the whole layout including the sidebar, so there was no other
    /// navigation either. The app works perfectly well with no client attached — notes can
    /// be written by hand — and a setup wall for an optional integration is the opposite of
    /// letting someone finish what they came to do.
    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Use Unli Rice without connecting") {
                store.showHome()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.accentColor)
            Text("You can connect later from More → Setup.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - State 1 View

    private var state1QuestionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your AI forgets you. Every single conversation.")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("You explain how you work to Claude. You explain it again to ChatGPT. Next week you explain it to Claude again, because it forgot.\n\nUnli Rice is one memory all of them read and write. Pick your primary tool to connect it in one step:")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 10)

                // 4 Choice Buttons
                HStack(spacing: 10) {
                    ForEach(ToolOption.allCases) { tool in
                        Button(action: { selectedTool = tool }) {
                            Text(tool.rawValue)
                                .font(.system(size: 13, weight: selectedTool == tool ? .bold : .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .foregroundStyle(selectedTool == tool ? Theme.accentColor : Theme.textPrimary)
                                .selectedControl(cornerRadius: 8, accent: Theme.accentColor, selected: selectedTool == tool)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().opacity(0.15)

                // Detail instruction card based on choice
                if let tool = selectedTool {
                    switch tool {
                    case .claude:
                        mcpToolInstruction(
                            toolName: "Claude Desktop",
                            configPath: "~/Library/Application Support/Claude/claude_desktop_config.json",
                            targetID: "claude-desktop"
                        )
                    case .cursor:
                        mcpToolInstruction(
                            toolName: "Cursor",
                            configPath: "~/.cursor/mcp.json",
                            targetID: "cursor"
                        )
                    case .chatgpt:
                        chatGPTInstruction
                    case .somethingElse:
                        somethingElseInstruction
                    }
                }
            }
            .padding(32)
        }
    }

    // MARK: - MCP Tool Instruction (Claude / Cursor)

    private func mcpToolInstruction(toolName: String, configPath: String, targetID: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Add this block to your \(toolName) config file:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text(configPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(6)
                    .background(Theme.bgField)
                    .cornerRadius(4)
            }

            if let target = store.availableTargets.first(where: { $0.id == targetID }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.snippet(for: target))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bgField)
                        .cornerRadius(6)

                    HStack {
                        Button("Copy configuration block") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.snippet(for: target), forType: .string)
                            store.statusMessage = "Copied \(toolName) configuration block to clipboard."
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.onSolidFill)
                        .solidControl(cornerRadius: 6)

                        Spacer()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("2. Restart \(toolName).")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Once restarted, \(toolName) connects to Unli Rice automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            if selectedTool == .claude {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().opacity(0.15)

                    Text("Index Claude Code Sessions")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Also index your Claude Code session logs? They're already on your Mac at ~/.claude/projects.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)

                    HStack {
                        Button("Select ~/.claude/projects Folder") {
                            store.chooseClaudeProjectsFolder()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.accentColor)
                        .solidControl(cornerRadius: 6)

                        if store.claudeProjectsURL != nil {
                            Text("✓ Access granted")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.emerald)
                        }
                    }
                }
            }

            // Live status dot
            liveStatusDot(toolName: toolName)
        }
        .padding(20)
        .liquidGlass(cornerRadius: 10)
    }

    private func liveStatusDot(toolName: String) -> some View {
        HStack(spacing: 8) {
            if let client = store.connectedClientName {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.emerald)
                Text("✓ \(client) is connected!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.emerald)
            } else {
                Circle()
                    .fill(Theme.brass)
                    .frame(width: 8, height: 8)
                Text("Waiting for \(toolName) to connect...")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Check again") {
                    store.refreshTrustCenter()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accentColor)
            }
        }
        .padding(12)
        .background(Theme.bgField)
        .cornerRadius(6)
    }

    // MARK: - ChatGPT Instruction

    private var chatGPTInstruction: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ChatGPT web cannot read local files directly.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Choose how you want to share memory with ChatGPT:")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Option A: Folder
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Theme.accentColor)
                    Text("Option A: The Unli Rice Folder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }

                Text("Creates a folder at `~/Documents/Unli Rice/` with your guardrails and notes ready for your AI to read.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Button("Set Up Unli Rice Folder") {
                    store.setupUnliRiceFolder()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.onSolidFill)
                .solidControl(cornerRadius: 6)
            }
            .padding(14)
            .background(Theme.bgField)
            .cornerRadius(8)

            // Option B: Copy Context
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.on.clipboard.fill")
                        .foregroundStyle(Theme.brass)
                    Text("Option B: Copy Context Button")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }

                Text("Copies your guardrails, memory capsule, and project notes formatted directly for pasting into a ChatGPT prompt.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Button("Copy context for ChatGPT") {
                    store.copyContextToClipboard()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(Theme.onSolidFill)
                .solidControl(cornerRadius: 6)
            }
            .padding(14)
            .background(Theme.bgField)
            .cornerRadius(8)
        }
        .padding(20)
        .liquidGlass(cornerRadius: 10)
    }

    // MARK: - Something Else Instruction

    private var somethingElseInstruction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Other AI Connectors")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Unli Rice supports any tool that speaks the Model Context Protocol (MCP) over standard IO.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)

            ConnectView()
        }
    }

    // MARK: - State 2 View

    private func state2ConnectedView(clientName: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.emerald)

            VStack(spacing: 8) {
                Text("✓ \(clientName) is connected.")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Try asking it in chat:")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)

                Text("\"Remember that I prefer short answers.\"")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.accentSoft)
                    .cornerRadius(8)
            }

            Text("That round trip is your persistent memory. As soon as your AI writes its first note, your memory goes live.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Continue to App →") {
                store.showHome()
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .foregroundStyle(Theme.onSolidFill)
            .solidControl(cornerRadius: 6)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Connected State 3 Fallback

    private var connectedState3View: some View {
        VStack(spacing: 16) {
            Text("Memory is connected and active.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Button("Go to Home") {
                store.showHome()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.onSolidFill)
            .solidControl(cornerRadius: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
