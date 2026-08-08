import Foundation

/// Input model collected by the Profile Builder wizard.
public struct ProfileBuilderInput: Sendable, Codable, Equatable {
    public var name: String
    public var role: String
    public var mission: String
    public var quirks: [String]
    public var persona: String
    public var customPersona: String
    public var toneRules: String
    public var formattingChips: [String]
    public var principles: [String]
    public var stackDefaults: String
    public var dosAndDonts: String
    public var guardrails: [String]
    public var includeExceptionRule: Bool
    public var projects: [ProjectEntry]
    public var overlays: [OverlayEntry]

    public struct ProjectEntry: Sendable, Codable, Identifiable, Equatable {
        public var id: UUID = UUID()
        public var name: String
        public var oneLiner: String
        public var status: String

        public init(id: UUID = UUID(), name: String = "", oneLiner: String = "", status: String = "Active") {
            self.id = id
            self.name = name
            self.oneLiner = oneLiner
            self.status = status
        }
    }

    public struct OverlayEntry: Sendable, Codable, Identifiable, Equatable {
        public var id: UUID = UUID()
        public var name: String
        public var rules: String

        public init(id: UUID = UUID(), name: String = "", rules: String = "") {
            self.id = id
            self.name = name
            self.rules = rules
        }
    }

    public init(
        name: String = "",
        role: String = "",
        mission: String = "",
        quirks: [String] = [],
        persona: String = "Concierge",
        customPersona: String = "",
        toneRules: String = "",
        formattingChips: [String] = [],
        principles: [String] = [],
        stackDefaults: String = "",
        dosAndDonts: String = "",
        guardrails: [String] = [],
        includeExceptionRule: Bool = true,
        projects: [ProjectEntry] = [],
        overlays: [OverlayEntry] = []
    ) {
        self.name = name
        self.role = role
        self.mission = mission
        self.quirks = quirks
        self.persona = persona
        self.customPersona = customPersona
        self.toneRules = toneRules
        self.formattingChips = formattingChips
        self.principles = principles
        self.stackDefaults = stackDefaults
        self.dosAndDonts = dosAndDonts
        self.guardrails = guardrails
        self.includeExceptionRule = includeExceptionRule
        self.projects = projects
        self.overlays = overlays
    }
}

/// Generates personalized `Profile:` context notes from `ProfileBuilderInput`.
public enum ProfileBuilder {
    public static let exceptionGuardrailRule = """
    If the user asks for something that contradicts these notes, ask whether it's a one-time exception or whether the note should change. One-time → note the exception in the session; change → append the change to the relevant note.
    """

    @discardableResult
    public static func generateNotes(from input: ProfileBuilderInput, noteService: NoteService) throws -> [Note] {
        var generatedNotes: [Note] = []

        // 1. Profile: identity
        let identityBody = """
        # Profile: Identity

        - **Name / Handle:** \(input.name.isEmpty ? "User" : input.name)
        - **Role / What you do:** \(input.role.isEmpty ? "Not specified" : input.role)
        - **Mission:** \(input.mission.isEmpty ? "Not specified" : input.mission)

        ## Quirks & Working Patterns
        \(input.quirks.isEmpty ? "None specified." : input.quirks.map { "- \($0)" }.joined(separator: "\n"))
        """
        if let note = try createOrAppend(title: "Profile: identity", body: identityBody, noteService: noteService) {
            generatedNotes.append(note)
        }

        // 2. Profile: voice
        let selectedPersona = input.persona == "Custom" ? (input.customPersona.isEmpty ? "Custom" : input.customPersona) : input.persona
        let voiceBody = """
        # Profile: Voice & Communication Style

        - **Persona:** \(selectedPersona)
        - **Tone Rules:** \(input.toneRules.isEmpty ? "Concierge voice: calm, short, non-judgmental, no hype." : input.toneRules)

        ## Formatting Rules
        \(input.formattingChips.isEmpty ? "- Keep responses concise\n- Use markdown formatting" : input.formattingChips.map { "- \($0)" }.joined(separator: "\n"))
        """
        if let note = try createOrAppend(title: "Profile: voice", body: voiceBody, noteService: noteService) {
            generatedNotes.append(note)
        }

        // 3. Profile: principles
        let principlesBody = """
        # Profile: Principles & Working Habits

        ## Core Principles
        \(input.principles.isEmpty ? "- Build for clarity and longevity." : input.principles.map { "- \($0)" }.joined(separator: "\n"))

        ## Tool & Stack Defaults
        \(input.stackDefaults.isEmpty ? "Not specified." : input.stackDefaults)

        ## Do's & Don'ts
        \(input.dosAndDonts.isEmpty ? "Not specified." : input.dosAndDonts)
        """
        if let note = try createOrAppend(title: "Profile: principles", body: principlesBody, noteService: noteService) {
            generatedNotes.append(note)
        }

        // 4. Profile: guardrails
        var guardrailsList = input.guardrails.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if input.includeExceptionRule {
            guardrailsList.append("Exception Guardrail: \(exceptionGuardrailRule)")
        }

        let guardrailsBody = """
        # Profile: Guardrails

        ## Non-Negotiables & Hard Constraints
        \(guardrailsList.isEmpty ? "- Always preserve user data integrity." : guardrailsList.map { "- \($0)" }.joined(separator: "\n"))
        """
        if let note = try createOrAppend(title: "Profile: guardrails", body: guardrailsBody, noteService: noteService) {
            generatedNotes.append(note)
        }

        // 5. Project notes — one note per project, mirroring how the author's
        // own vault is organized: the roster lives in the index, the substance
        // lives in a note per project that agents append to as work happens.
        let namedProjects = input.projects.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        for project in namedProjects {
            let projectBody = """
            # Project: \(project.name)

            - **Status:** \(project.status)
            - **Overview:** \(project.oneLiner.isEmpty ? "Not specified" : project.oneLiner)

            ## Log
            Append dated entries below — what was decided and why, kept terse. \
            Implementation detail belongs in the project's own repo, referenced by path.
            """
            if let note = try createOrAppend(title: "Project: \(project.name)", body: projectBody, tag: "project", noteService: noteService) {
                generatedNotes.append(note)
            }
        }

        // 6. Overlays
        for overlay in input.overlays where !overlay.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let overlayTitle = "Profile: overlay \(overlay.name.lowercased())"
            let overlayBody = """
            # Profile Overlay: \(overlay.name)

            \(overlay.rules)
            """
            if let note = try createOrAppend(title: overlayTitle, body: overlayBody, noteService: noteService) {
                generatedNotes.append(note)
            }
        }

        // 7. Profile: index (Master Context index)
        let indexBody = """
        # Profile: Index (Master Context)

        This is the central sitemap for this profile's AI context documents.

        - [[Profile: identity]] — Identity, role, mission, and working patterns.
        - [[Profile: voice]] — Persona, tone, and response formatting rules.
        - [[Profile: principles]] — Working principles, stack defaults, and conventions.
        - [[Profile: guardrails]] — Non-negotiable rules and the exception guardrail.
        \(namedProjects.map { "- [[Project: \($0.name)]] — \($0.oneLiner.isEmpty ? $0.status : $0.oneLiner)\n" }.joined())\
        \(input.overlays.map { "- [[Profile: overlay \($0.name.lowercased())]] — Overlay rules for \($0.name)." }.joined(separator: "\n"))
        """
        if let note = try createOrAppend(title: "Profile: index", body: indexBody, noteService: noteService) {
            generatedNotes.append(note)
        }

        return generatedNotes
    }

    private static func createOrAppend(title: String, body: String, tag: String = "profile", noteService: NoteService) throws -> Note? {
        let existing = try noteService.searchNotes(query: title)
        let wrappedContent = ProfileRevision.wrapped(body, title: title)
        if let match = existing.first(where: { $0.title.lowercased() == title.lowercased() }) {
            return try noteService.appendToNote(
                id: match.id,
                text: "\n\n---\n\n\(wrappedContent)",
                source: "unlirice"
            )
        } else {
            let note = try noteService.createNote(
                title: title,
                body: wrappedContent,
                source: "unlirice"
            )
            _ = try? noteService.tagNote(id: note.id, tag: tag, source: "unlirice")
            return note
        }
    }
}
