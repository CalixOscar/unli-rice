import UnliRiceCore
import SwiftUI

/// Form-based wizard for creating/updating a personalized `Profile:` document set.
struct ProfileBuilderView: View {
    @EnvironmentObject var store: AppStore
    @State private var step: Step = .whoYouAre
    @State private var input = ProfileBuilderInput()
    @State private var selectedTemplateID: String = ""
    @State private var newQuirkText = ""
    @State private var newFormattingText = ""
    @State private var newPrincipleText = ""
    @State private var newGuardrailText = ""

    enum Step: Int, CaseIterable, Identifiable {
        case whoYouAre = 1
        case personaAndVoice = 2
        case principlesAndWork = 3
        case guardrails = 4
        case projects = 5
        case overlays = 6

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .whoYouAre: return "1. Who You Are"
            case .personaAndVoice: return "2. Voice & Persona"
            case .principlesAndWork: return "3. Principles & Work"
            case .guardrails: return "4. Guardrails"
            case .projects: return "5. Projects"
            case .overlays: return "6. Overlays (Optional)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile Builder")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Step \(step.rawValue) of 6 — \(step.title)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                // Template picker dropdown. Templates are starting points, not
                // packages: load one whole, pull a single step from one, or mix
                // steps from different templates.
                Menu {
                    Section("Load full template") {
                        ForEach(ProfileTemplate.builtIn) { template in
                            Button(template.title) {
                                applyTemplate(template)
                            }
                        }
                    }
                    Section("Pre-fill this step only") {
                        ForEach(ProfileTemplate.builtIn) { template in
                            Button(template.title) {
                                applyTemplate(template, onlyCurrentStep: true)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text(selectedTemplateID.isEmpty ? "Load Template…" : "Template Loaded")
                    }
                    .font(.system(size: 11.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .solidControl(cornerRadius: 6)
            }

            // Step Progress Indicator
            HStack(spacing: 4) {
                ForEach(Step.allCases) { s in
                    Rectangle()
                        .fill(s.rawValue <= step.rawValue ? Theme.accentColor : Theme.borderLight)
                        .frame(height: 3)
                        .clipShape(Capsule())
                }
            }

            // Step Form Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case .whoYouAre:
                        whoYouAreStep
                    case .personaAndVoice:
                        personaAndVoiceStep
                    case .principlesAndWork:
                        principlesAndWorkStep
                    case .guardrails:
                        guardrailsStep
                    case .projects:
                        projectsStep
                    case .overlays:
                        overlaysStep
                    }
                }
                .padding(.vertical, 4)
            }

            // Navigation Buttons
            HStack {
                if step.rawValue > 1 {
                    Button("Back") {
                        if let prev = Step(rawValue: step.rawValue - 1) {
                            step = prev
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(Theme.onSolidFill)
                    .solidControl(cornerRadius: 6)
                }

                Button("Skip Step") {
                    advanceStep()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .foregroundStyle(Theme.textSecondary)

                Spacer()

                if step == .overlays {
                    Button("Finish & Generate Profile Notes") {
                        finishAndGenerate()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Button("Next →") {
                        advanceStep()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Step 1: Who You Are
    private var whoYouAreStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            formField(label: "Your Name / Handle", hint: "How AI tools should address you.") {
                TextField("e.g. Alex", text: $input.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }

            formField(label: "What You Do", hint: "Your primary role or focus.") {
                TextField("e.g. Lead Engineer, Product Designer, Founder", text: $input.role)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }

            formField(label: "Mission in One Sentence", hint: "What drives your current work.") {
                TextField("e.g. Building fast, reliable local software.", text: $input.mission)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Quirks & Working Patterns")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                HStack {
                    chipToggle("many ideas, weak finisher", set: $input.quirks)
                    chipToggle("mockups drift", set: $input.quirks)
                    chipToggle("outline-first", set: $input.quirks)
                    chipToggle("concise code", set: $input.quirks)
                }

                // Every quirk currently set — including ones typed in below or
                // loaded from a template that don't match a preset chip above —
                // shown with its own remove control. Without this list, a
                // custom or template-loaded quirk could be added but never
                // seen or taken back out again.
                removableList(input.quirks) { quirk in
                    input.quirks.removeAll { $0 == quirk }
                }

                HStack {
                    TextField("Add custom quirk…", text: $newQuirkText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    Button("Add") {
                        if !newQuirkText.isEmpty {
                            input.quirks.append(newQuirkText)
                            newQuirkText = ""
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentColor)
                }
                .padding(6)
                .background(Theme.bgField)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))
            }
        }
    }

    // MARK: - Step 2: Voice & Persona
    private var personaAndVoiceStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            formField(label: "AI Persona", hint: "Select the tone and role your AI should adopt.") {
                Picker("", selection: $input.persona) {
                    Text("Concierge (Calm, short, non-judgmental)").tag("Concierge")
                    Text("Coach (Encouraging, structured, guiding)").tag("Coach")
                    Text("Peer (Collaborative, direct, technical)").tag("Peer")
                    Text("Terse Tool (Ultra-short, no fluff)").tag("Terse Tool")
                    Text("Custom").tag("Custom")
                }
                .pickerStyle(.menu)
            }

            if input.persona == "Custom" {
                formField(label: "Custom Persona Description", hint: "Describe your custom persona.") {
                    TextField("e.g. Socratic mentor who asks guiding questions.", text: $input.customPersona)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                }
            }

            formField(label: "Tone Rules", hint: "Specific instructions on tone.") {
                TextField("e.g. Avoid hype, no buzzwords, stay calm and direct.", text: $input.toneRules)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Formatting Preferences")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                HStack {
                    chipToggle("short answers", set: $input.formattingChips)
                    chipToggle("no emoji", set: $input.formattingChips)
                    chipToggle("no hype", set: $input.formattingChips)
                    chipToggle("code blocks with tags", set: $input.formattingChips)
                }

                removableList(input.formattingChips) { chip in
                    input.formattingChips.removeAll { $0 == chip }
                }

                HStack {
                    TextField("Add custom formatting rule…", text: $newFormattingText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    Button("Add") {
                        if !newFormattingText.isEmpty {
                            input.formattingChips.append(newFormattingText)
                            newFormattingText = ""
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentColor)
                }
                .padding(6)
                .background(Theme.bgField)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))
            }
        }
    }

    // MARK: - Step 3: Principles & Work
    private var principlesAndWorkStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            formField(label: "Tool & Stack Defaults", hint: "Languages, frameworks, or default tools you use.") {
                TextField("e.g. Swift, TypeScript, Xcode, Git, Tailwind", text: $input.stackDefaults)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }

            formField(label: "Things to Always / Never Do", hint: "Standing conventions for your code or text.") {
                TextField("e.g. DO run unit tests. DON'T alter public function signatures without updating callers.", text: $input.dosAndDonts)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Core Principles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                ForEach(input.principles, id: \.self) { p in
                    HStack {
                        Text("• \(p)").font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button("Remove") {
                            input.principles.removeAll { $0 == p }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.crit)
                    }
                }

                HStack {
                    TextField("Add a principle…", text: $newPrincipleText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    Button("Add") {
                        if !newPrincipleText.isEmpty {
                            input.principles.append(newPrincipleText)
                            newPrincipleText = ""
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentColor)
                }
                .padding(6)
                .background(Theme.bgField)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))
            }
        }
    }

    // MARK: - Step 4: Guardrails
    private var guardrailsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guardrails are hard constraints your AI assistants must obey at all times.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            // Exception Guardrail Box
            Toggle(isOn: $input.includeExceptionRule) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Standing Exception Guardrail (Mandatory Recommendation)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.brass)
                    Text("“If the user asks for something that contradicts these notes, ask whether it's a one-time exception or whether the note should change.”")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
            .liquidGlass(cornerRadius: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text("Non-Negotiable Guardrails")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                ForEach(input.guardrails, id: \.self) { g in
                    HStack {
                        Text("• \(g)").font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Button("Remove") {
                            input.guardrails.removeAll { $0 == g }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.crit)
                    }
                }

                HStack {
                    TextField("Add custom non-negotiable rule…", text: $newGuardrailText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    Button("Add") {
                        if !newGuardrailText.isEmpty {
                            input.guardrails.append(newGuardrailText)
                            newGuardrailText = ""
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentColor)
                }
                .padding(6)
                .background(Theme.bgField)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))
            }
        }
    }

    // MARK: - Step 5: Projects
    private var projectsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("List active projects so connected AI tools understand your ongoing work.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            ForEach($input.projects) { $project in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Project Name", text: $project.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Button("Remove") {
                            let idToRemove = project.id
                            input.projects.removeAll { $0.id == idToRemove }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.crit)
                    }
                    TextField("One-line overview", text: $project.oneLiner)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    TextField("Status (e.g. Active, Paused, Shipped)", text: $project.status)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(10)
                .liquidGlass(cornerRadius: 6)
            }

            Button("+ Add Project") {
                input.projects.append(ProfileBuilderInput.ProjectEntry())
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.accentColor)
        }
    }

    // MARK: - Step 6: Overlays
    private var overlaysStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optional platform or domain-specific overlays (e.g. Apple, Web, Cloud).")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            ForEach($input.overlays) { $overlay in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Overlay Name (e.g. Apple)", text: $overlay.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Button("Remove") {
                            let idToRemove = overlay.id
                            input.overlays.removeAll { $0.id == idToRemove }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.crit)
                    }
                    TextEditor(text: $overlay.rules)
                        .font(.system(size: 12))
                        .frame(height: 60)
                }
                .padding(10)
                .liquidGlass(cornerRadius: 6)
            }

            HStack(spacing: 14) {
                Button("+ Add Overlay") {
                    input.overlays.append(ProfileBuilderInput.OverlayEntry())
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accentColor)

                Menu {
                    ForEach(OverlayTemplate.builtIn) { template in
                        Button {
                            input.overlays.append(template.makeEntry())
                        } label: {
                            Text(template.title)
                            Text(template.summary)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                        Text("Load Overlay Template…")
                    }
                    .font(.system(size: 11.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Helpers
    private func formField<Content: View>(label: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            content()
                .padding(7)
                .background(Theme.bgField)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.borderLight, lineWidth: 1))
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Every item currently in a string array, with its own remove control.
    /// Used alongside preset chips so anything in the array — chip-selected,
    /// typed by hand, or loaded from a template — stays visible and takable-
    /// back-out, never invisible state the UI can add to but not show.
    private func removableList(_ items: [String], onRemove: @escaping (String) -> Void) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            HStack {
                Text("• \(item)").font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Remove") {
                    onRemove(item)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.crit)
            }
        }
    }

    private func chipToggle(_ label: String, set: Binding<[String]>) -> some View {
        let isSelected = set.wrappedValue.contains(label)
        return Button(action: {
            if isSelected {
                set.wrappedValue.removeAll { $0 == label }
            } else {
                set.wrappedValue.append(label)
            }
        }) {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Theme.accentSoft : Theme.solidFill)
                .foregroundStyle(isSelected ? Theme.accentColor : Theme.textSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Theme.accentColor : Theme.solidStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func advanceStep() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func applyTemplate(_ template: ProfileTemplate, onlyCurrentStep: Bool = false) {
        selectedTemplateID = template.id
        guard onlyCurrentStep else {
            input = template.input
            return
        }
        let t = template.input
        switch step {
        case .whoYouAre:
            input.name = t.name
            input.role = t.role
            input.mission = t.mission
            input.quirks = t.quirks
        case .personaAndVoice:
            input.persona = t.persona
            input.customPersona = t.customPersona
            input.toneRules = t.toneRules
            input.formattingChips = t.formattingChips
        case .principlesAndWork:
            input.principles = t.principles
            input.stackDefaults = t.stackDefaults
            input.dosAndDonts = t.dosAndDonts
        case .guardrails:
            input.guardrails = t.guardrails
            input.includeExceptionRule = t.includeExceptionRule
        case .projects:
            input.projects = t.projects
        case .overlays:
            input.overlays = t.overlays
        }
    }

    private func finishAndGenerate() {
        do {
            try ProfileBuilder.generateNotes(from: input, noteService: store.service)
            store.reload()
            store.showGetStarted()
        } catch {
            store.errorMessage = "Failed to generate profile notes: \(error)"
        }
    }
}
