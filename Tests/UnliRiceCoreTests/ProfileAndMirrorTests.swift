import XCTest
@testable import UnliRiceCore

final class ProfileAndMirrorTests: XCTestCase {
    var tempDirectory: URL!
    var eventLogURL: URL!
    var noteService: NoteService!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        eventLogURL = tempDirectory.appendingPathComponent("events.jsonl")
        noteService = try NoteService(store: EventStore(fileURL: eventLogURL))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testProfileBuilderGeneratesNotesAndIndex() throws {
        let input = ProfileBuilderInput(
            name: "Alex",
            role: "Developer",
            mission: "Build great tools",
            quirks: ["concise code"],
            persona: "Concierge",
            toneRules: "Calm and concise",
            formattingChips: ["no emoji"],
            principles: ["Build for longevity"],
            stackDefaults: "Swift, Xcode",
            dosAndDonts: "DO test code",
            guardrails: ["Never delete files autonomously"],
            includeExceptionRule: true
        )

        let notes = try ProfileBuilder.generateNotes(from: input, noteService: noteService)
        XCTAssertGreaterThanOrEqual(notes.count, 5)

        let allNotes = try noteService.listNotes(includeArchived: false)
        XCTAssertTrue(allNotes.contains { $0.title == "Profile: identity" })
        XCTAssertTrue(allNotes.contains { $0.title == "Profile: voice" })
        XCTAssertTrue(allNotes.contains { $0.title == "Profile: principles" })
        XCTAssertTrue(allNotes.contains { $0.title == "Profile: guardrails" })
        XCTAssertTrue(allNotes.contains { $0.title == "Profile: index" })

        guard let guardrailsNote = allNotes.first(where: { $0.title == "Profile: guardrails" }) else {
            XCTFail("Missing guardrails note")
            return
        }
        XCTAssertTrue(guardrailsNote.body.contains("Exception Guardrail"))
        XCTAssertTrue(guardrailsNote.tags.contains("profile"))
        XCTAssertTrue(guardrailsNote.sources.contains("unlirice"))
    }

    func testProfileBuilderRerunAppendsRevisionsWithoutDuplicateTitles() throws {
        let input1 = ProfileBuilderInput(name: "Version 1", persona: "Peer")
        _ = try ProfileBuilder.generateNotes(from: input1, noteService: noteService)

        let countBefore = try noteService.listNotes(includeArchived: false).count

        let input2 = ProfileBuilderInput(name: "Version 2", persona: "Coach")
        _ = try ProfileBuilder.generateNotes(from: input2, noteService: noteService)

        let allNotes = try noteService.listNotes(includeArchived: false)
        XCTAssertEqual(allNotes.count, countBefore)

        let identityNote = allNotes.first { $0.title == "Profile: identity" }
        XCTAssertNotNil(identityNote)
        XCTAssertTrue(identityNote!.body.contains("Version 2"))
        XCTAssertTrue(identityNote!.body.contains("Revision"))
    }

    func testProfileRegistryCreatesAndManagesProfiles() throws {
        let registryFile = tempDirectory.appendingPathComponent("profiles.json")
        let registry = ProfileRegistry(storageURL: registryFile)

        XCTAssertEqual(registry.profiles.count, 1)
        XCTAssertTrue(registry.profiles.first?.isMaster == true)

        let newProfile = registry.createProfile(name: "Work Vault", folderPath: tempDirectory.path)
        XCTAssertEqual(registry.profiles.count, 2)
        XCTAssertEqual(newProfile.name, "Work Vault")

        registry.setMasterProfile(id: newProfile.id)
        XCTAssertEqual(registry.masterProfile?.id, newProfile.id)
    }

    func testMirrorExporterExportsDerivedMarkdownFolder() throws {
        let input = ProfileBuilderInput(name: "Mirror User", persona: "Peer", guardrails: ["Rule 1"])
        _ = try ProfileBuilder.generateNotes(from: input, noteService: noteService)

        // Create Memory capsule note
        _ = try noteService.createNote(title: "Memory: capsule", body: "This is the memory capsule content under 2500 chars.", source: "claude")

        let result = try MirrorExporter.exportMirror(
            profileName: "Mirror Profile",
            vaultFolderURL: tempDirectory,
            noteService: noteService,
            houseRulesText: "Sample house rules"
        )

        let exportDir = result.exportDirectoryURL
        let contextDir = exportDir.appendingPathComponent("Context", isDirectory: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextDir.appendingPathComponent("00_Index.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextDir.appendingPathComponent("01_Identity.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextDir.appendingPathComponent("MEMORY.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextDir.appendingPathComponent("HOUSE_RULES.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("READ ME FIRST.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("Notes for Unli Rice").path))

        XCTAssertEqual(result.memoryCapsuleLength, 52)
        XCTAssertFalse(result.memoryCapsuleExceeded)
    }

    func testStandardTemplateIsFirstAndDemonstratesEveryStep() {
        let standard = ProfileTemplate.standard
        XCTAssertEqual(ProfileTemplate.builtIn.first?.id, standard.id)
        // The standard template is the worked example: unlike the alternatives
        // it must exercise every wizard step, including projects and overlays.
        XCTAssertFalse(standard.input.projects.isEmpty)
        XCTAssertFalse(standard.input.overlays.isEmpty)
        XCTAssertFalse(standard.input.guardrails.isEmpty)
        XCTAssertTrue(standard.input.includeExceptionRule)
    }

    func testProjectsGenerateOneNotePerProjectLinkedFromIndex() throws {
        let input = ProfileBuilderInput(
            name: "Alex",
            projects: [
                ProfileBuilderInput.ProjectEntry(name: "Alpha", oneLiner: "First project", status: "Active"),
                ProfileBuilderInput.ProjectEntry(name: "Beta", oneLiner: "Second project", status: "Paused"),
                ProfileBuilderInput.ProjectEntry(name: "   ", oneLiner: "Unnamed, must be skipped", status: "Active"),
            ]
        )
        _ = try ProfileBuilder.generateNotes(from: input, noteService: noteService)

        let allNotes = try noteService.listNotes(includeArchived: false)
        let alpha = allNotes.first { $0.title == "Project: Alpha" }
        let beta = allNotes.first { $0.title == "Project: Beta" }
        XCTAssertNotNil(alpha)
        XCTAssertNotNil(beta)
        XCTAssertTrue(alpha!.tags.contains("project"))
        XCTAssertFalse(allNotes.contains { $0.title == "Profile: projects" })
        XCTAssertEqual(allNotes.filter { $0.title.hasPrefix("Project: ") }.count, 2)

        let index = allNotes.first { $0.title == "Profile: index" }
        XCTAssertNotNil(index)
        XCTAssertTrue(index!.body.contains("[[Project: Alpha]]"))
        XCTAssertTrue(index!.body.contains("[[Project: Beta]]"))
        XCTAssertTrue(index!.outboundLinks.contains(alpha!.id))
    }

    func testMirrorExportMatchesExactTitlesNotPrefixes() throws {
        let input = ProfileBuilderInput(name: "Real Identity", persona: "Peer")
        _ = try ProfileBuilder.generateNotes(from: input, noteService: noteService)
        // A user note whose title extends the canonical one must never be
        // exported in its place, regardless of list order.
        _ = try noteService.createNote(
            title: "Profile: identity — old draft",
            body: "STALE DRAFT",
            source: "human"
        )

        let result = try MirrorExporter.exportMirror(
            profileName: "Exact Match",
            vaultFolderURL: tempDirectory,
            noteService: noteService
        )

        let contextDir = result.exportDirectoryURL.appendingPathComponent("Context", isDirectory: true)
        let identity = try String(contentsOf: contextDir.appendingPathComponent("01_Identity.md"), encoding: .utf8)
        XCTAssertTrue(identity.contains("Real Identity"))
        XCTAssertFalse(identity.contains("STALE DRAFT"))
    }

    func testMirrorExportsOverlayAndProjectFiles() throws {
        let input = ProfileBuilderInput(
            name: "Alex",
            projects: [ProfileBuilderInput.ProjectEntry(name: "Alpha", oneLiner: "First project", status: "Active")],
            overlays: [
                ProfileBuilderInput.OverlayEntry(name: "Apple", rules: "Swift first."),
                ProfileBuilderInput.OverlayEntry(name: "Web", rules: "Static first."),
            ]
        )
        _ = try ProfileBuilder.generateNotes(from: input, noteService: noteService)

        let result = try MirrorExporter.exportMirror(
            profileName: "Full Set",
            vaultFolderURL: tempDirectory,
            noteService: noteService
        )

        let contextDir = result.exportDirectoryURL.appendingPathComponent("Context", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextDir.appendingPathComponent("05_Overlay_Apple.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextDir.appendingPathComponent("06_Overlay_Web.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextDir.appendingPathComponent("PROJECTS/Alpha.md").path))

        let project = try String(contentsOf: contextDir.appendingPathComponent("PROJECTS/Alpha.md"), encoding: .utf8)
        XCTAssertTrue(project.contains("First project"))
    }

    func testHouseRulesPresetsContainExceptionGuardrail() {
        for preset in HouseRulesPreset.builtIn {
            XCTAssertTrue(preset.body.contains("Exception Guardrail") || preset.body.contains("contradicts"))
        }
    }

    func testMirrorExporterEmitsClaudeAndAgentsConventionFiles() throws {
        let input = ProfileBuilderInput(name: "Vault Mode User", persona: "Peer", guardrails: ["Rule 1"])
        _ = try ProfileBuilder.generateNotes(from: input, noteService: noteService)

        let result = try MirrorExporter.exportMirror(
            profileName: "Vault Mode Profile",
            vaultFolderURL: tempDirectory,
            noteService: noteService
        )

        let dir = result.exportDirectoryURL
        let claudeURL = dir.appendingPathComponent("CLAUDE.md")
        let agentsURL = dir.appendingPathComponent("AGENTS.md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: claudeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agentsURL.path))

        let claudeContent = try String(contentsOf: claudeURL, encoding: .utf8)
        let agentsContent = try String(contentsOf: agentsURL, encoding: .utf8)

        XCTAssertEqual(claudeContent, agentsContent)
        XCTAssertTrue(claudeContent.contains("Vault Mode Profile"))
        XCTAssertTrue(claudeContent.contains("✅ Unli Rice vault connected — 5 notes, profile \"Vault Mode Profile\"."))
        XCTAssertTrue(claudeContent.contains("If you found no relevant notes, say so instead. Never claim otherwise."))
    }

    func testMirrorExporterEmptyVaultEmitsZeroNoteCountConvention() throws {
        let result = try MirrorExporter.exportMirror(
            profileName: "Empty Vault Profile",
            vaultFolderURL: tempDirectory,
            noteService: noteService
        )

        let dir = result.exportDirectoryURL
        let claudeURL = dir.appendingPathComponent("CLAUDE.md")
        let claudeContent = try String(contentsOf: claudeURL, encoding: .utf8)

        XCTAssertTrue(claudeContent.contains("0 notes"))
        XCTAssertTrue(claudeContent.contains("✅ Unli Rice vault connected — 0 notes, profile \"Empty Vault Profile\"."))
    }
}

