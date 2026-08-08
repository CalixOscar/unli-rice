import AppKit
import SwiftUI
import UnliRiceCore

struct ProfileEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    struct SectionItem: Identifiable, Hashable {
        let id: String
        let title: String
        let displayName: String
    }

    let sections: [SectionItem] = [
        SectionItem(id: "identity", title: "Profile: identity", displayName: "Identity"),
        SectionItem(id: "voice", title: "Profile: voice", displayName: "Voice & Tone"),
        SectionItem(id: "principles", title: "Profile: principles", displayName: "Principles"),
        SectionItem(id: "capsule", title: MirrorExporter.memoryCapsuleTitle, displayName: "Memory Capsule")
    ]

    @State private var selectedSection: SectionItem
    @State private var draftText: String = ""
    @State private var originalBody: String = ""
    @State private var feedbackMessage: String?

    init(initialSectionTitle: String = "Profile: identity") {
        let defaultSection = SectionItem(id: "identity", title: "Profile: identity", displayName: "Identity")
        let match = [
            SectionItem(id: "identity", title: "Profile: identity", displayName: "Identity"),
            SectionItem(id: "voice", title: "Profile: voice", displayName: "Voice & Tone"),
            SectionItem(id: "principles", title: "Profile: principles", displayName: "Principles"),
            SectionItem(id: "capsule", title: MirrorExporter.memoryCapsuleTitle, displayName: "Memory Capsule")
        ].first { $0.title.lowercased() == initialSectionTitle.lowercased() } ?? defaultSection
        _selectedSection = State(initialValue: match)
    }

    var isUnchanged: Bool {
        ProfileRevision.noteContainsCurrentRevision(noteBody: originalBody, draftBody: draftText)
    }

    var isCapsule: Bool {
        selectedSection.title.lowercased() == MirrorExporter.memoryCapsuleTitle.lowercased()
    }

    enum CapsuleState {
        case missing
        case normal
        case oversized
    }

    var capsuleState: CapsuleState {
        if originalBody.isEmpty {
            return .missing
        } else if draftText.count > 2500 {
            return .oversized
        } else {
            return .normal
        }
    }

    var capsuleButtonTitle: String {
        switch capsuleState {
        case .missing:
            return "Write my capsule"
        case .normal:
            return "Refresh my capsule"
        case .oversized:
            return "Condense this"
        }
    }

    var sectionExplanation: String {
        if isCapsule {
            return "The short version of your memory. Your notes are too much to paste into a chat; this is the ~2,500-character summary worth pasting instead. Your AI writes it — press the button below."
        }
        switch selectedSection.id {
        case "identity":
            return "Who you are and what you're working on. Tells your AI how to introduce you."
        case "voice":
            return "How you prefer your AI to communicate (e.g. short answers, concise, no emoji)."
        case "principles":
            return "Standing rules and core principles your AI should always respect."
        default:
            return "Standing notes used by your connected AI tools."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit What Your AI Knows")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Saving adds a new version. Your old wording is kept — nothing is ever written over.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentColor)
            }

            // Section Picker
            Picker("Section", selection: $selectedSection) {
                ForEach(sections) { sec in
                    Text(sec.displayName).tag(sec)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedSection) { newSec in
                loadSection(newSec)
            }

            // Section Explanation Banner
            Text(sectionExplanation)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgField.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Text Editor Card
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $draftText)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.bgField)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minHeight: 160, maxHeight: 220)
            }

            // Feedback Toast if any
            if let feedback = feedbackMessage {
                Text(feedback)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.emerald)
                    .transition(.opacity)
            }

            Divider().opacity(0.12)

            // Buttons: Save & State-Aware Capsule / LLM Buttons (R6.3 & R7.2)
            HStack(spacing: 10) {
                // Save Button (disabled when text is unchanged)
                Button(action: saveCurrentSection) {
                    Text("Save Revision")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(isUnchanged ? Theme.textSecondary : Theme.onSolidFill)
                        .solidControl(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .disabled(isUnchanged)

                Spacer()

                if isCapsule {
                    // State-Aware Capsule Prompt Button (R7.2)
                    Button(action: handleCapsulePromptAction) {
                        HStack(spacing: 4) {
                            Image(systemName: capsuleState == .oversized ? "scissors" : "sparkles")
                            Text(capsuleButtonTitle)
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(capsuleState == .oversized ? Theme.brass : Theme.accentColor)
                        .solidControl(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                } else {
                    // LLM Button 1 — Copy for my AI to edit
                    Button(action: copyForAIToEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy for AI to edit")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.accentColor)
                        .solidControl(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)

                    // LLM Button 2 — Ask my AI to interview me
                    Button(action: askAIToInterviewMe) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right")
                            Text("Ask AI to interview me")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.brass)
                        .solidControl(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(22)
        .frame(width: 640, height: 460)
        .background(Theme.bgMain)
        .onAppear {
            loadSection(selectedSection)
        }
    }

    private func loadSection(_ sec: SectionItem) {
        if let rawNote = store.note(title: sec.title) {
            originalBody = rawNote.body
            draftText = ProfileRevision.latestBody(in: rawNote.body)
        } else {
            originalBody = ""
            draftText = ""
        }
        feedbackMessage = nil
    }

    private func saveCurrentSection() {
        store.saveProfileSection(title: selectedSection.title, body: draftText)
        loadSection(selectedSection)
        showFeedback("Saved new revision for \(selectedSection.displayName).")
    }

    private func handleCapsulePromptAction() {
        let prompt: String
        switch capsuleState {
        case .missing:
            prompt = "Read my Unli Rice notes and write a ≤2,500-character summary of what a new AI would need to know about me. Save it with `create_note` titled `Memory: capsule`."
        case .normal:
            prompt = "Read my Unli Rice notes and write a ≤2,500-character summary of what a new AI would need to know about me. Append the result to `Memory: capsule`."
        case .oversized:
            prompt = "This is over 2,500 characters. Rewrite it shorter, keeping only what a cold-start AI must know, and append the result to `Memory: capsule`."
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        showFeedback("Copied prompt for your AI to clipboard.")
    }

    private func copyForAIToEdit() {
        let payload = """
        Please edit my Unli Rice profile section '\(selectedSection.title)'.
        Here is the current text:

        \(draftText)

        Suggest improvements or update it directly using append_to_note on '\(selectedSection.title)'.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        showFeedback("Copied '\(selectedSection.displayName)' text and edit instructions to clipboard.")
    }

    private func askAIToInterviewMe() {
        let prompt = """
        Interview me about my working style and update my Unli Rice profile.
        Ask a few questions first, then write the answers back with append_to_note on '\(selectedSection.title)'.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        showFeedback("Copied interview prompt to clipboard.")
    }

    private func showFeedback(_ text: String) {
        withAnimation {
            feedbackMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                feedbackMessage = nil
            }
        }
    }
}
