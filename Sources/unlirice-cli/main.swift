import Foundation
import UnliRiceCore
import UnliRiceHost

struct CLIError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class UnliRiceCLI {
    let service: NoteService
    let logURL: URL
    let settings: AgentSettings
    let isJSON: Bool

    init(settings: AgentSettings, logURL: URL, service: NoteService, isJSON: Bool) {
        self.settings = settings
        self.logURL = logURL
        self.service = service
        self.isJSON = isJSON
    }

    func output<T: Encodable>(_ payload: T, humanReadable: String) throws {
        if isJSON {
            let jsonObject = try JSONRPC.plain(payload)
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            if let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print(humanReadable)
        }
    }

    func run(args: [String]) throws {
        guard let command = args.first else {
            printUsage()
            return
        }

        let options = parseOptions(Array(args.dropFirst()))
        let positional = options.positional

        switch command {
        case "note":
            try handleNoteCommands(positional: positional, options: options)

        case "tag":
            let source = try requireSource(options)
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: positional)
            let tag = try requireString(options, key: "tag", positionalIndex: 1, positional: positional)
            let note = try service.tagNote(id: id, tag: tag, source: source)
            try output(note, humanReadable: "Tagged note \"\(note.title)\" [\(note.id)] with '\(tag)'")

        case "untag":
            let source = try requireSource(options)
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: positional)
            let tag = try requireString(options, key: "tag", positionalIndex: 1, positional: positional)
            let note = try service.untagNote(id: id, tag: tag, source: source)
            try output(note, humanReadable: "Removed tag '\(tag)' from note \"\(note.title)\" [\(note.id)]")

        case "archive":
            let source = try requireSource(options)
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: positional)
            let reason = options.flags["reason"] ?? positional.dropFirst().joined(separator: " ")
            guard !reason.isEmpty else { throw CLIError(message: "Missing required argument: --reason <text>") }
            let note = try service.archiveNote(id: id, reason: reason, source: source)
            try output(note, humanReadable: "Archived note \"\(note.title)\" [\(note.id)]")

        case "unarchive":
            let source = try requireSource(options)
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: positional)
            let note = try service.unarchiveNote(id: id, source: source)
            try output(note, humanReadable: "Unarchived note \"\(note.title)\" [\(note.id)]")

        case "flag":
            let source = try requireSource(options)
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: positional)
            let reason = try requireString(options, key: "reason", positionalIndex: 1, positional: positional)
            let note = try service.flagForReview(id: id, reason: reason, source: source)
            try output(note, humanReadable: "Flagged note \"\(note.title)\" [\(note.id)] for review: \(reason)")

        case "reviews", "pending_reviews":
            let reviews = try service.pendingReviews()
            if isJSON {
                let payload = reviews.map { entry -> [String: Any] in
                    let notePayload = (try? JSONRPC.plain(entry.note)) ?? [:]
                    let flagPayload = (try? JSONRPC.plain(entry.flag)) ?? [:]
                    return ["note": notePayload, "flag": flagPayload]
                }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                if let str = String(data: data, encoding: .utf8) { print(str) }
            } else {
                if reviews.isEmpty {
                    print("No pending reviews.")
                } else {
                    print("Pending reviews (\(reviews.count)):")
                    for r in reviews {
                        print("- [Note \(r.note.id)] \"\(r.note.title)\"")
                        print("  Flag: \(r.flag.reason) (by \(r.flag.source) at \(r.flag.timestamp))")
                    }
                }
            }

        case "resolve":
            let source = try requireSource(options)
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: positional)
            let flagId = try requireUUID(options, key: "flag-id", positionalIndex: 1, positional: positional)
            let outcome = options.flags["outcome"]
            let note = try service.resolveReview(id: id, flagId: flagId, source: source, outcome: outcome)
            try output(note, humanReadable: "Resolved review flag on note \"\(note.title)\" [\(note.id)]")

        case "log", "transaction_log":
            let limitStr = options.flags["limit"] ?? positional.first ?? "50"
            let limit = Int(limitStr) ?? 50
            let events = try service.transactionLog(limit: limit)
            try output(events, humanReadable: events.map { "[\($0.timestamp)] \($0.kind) by \($0.source)" }.joined(separator: "\n"))

        case "project":
            guard positional.first == "init" else {
                throw CLIError(message: "Unknown project subcommand. Usage: unlirice project init <name>")
            }
            let name = positional.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                throw CLIError(message: "Missing project name. Usage: unlirice project init <name>")
            }
            try initProject(name: name, options: options)

        case "help", "--help", "-h":
            printUsage()

        default:
            throw CLIError(message: "Unknown command: '\(command)'. Run 'unlirice help' for usage.")
        }
    }

    private func handleNoteCommands(positional: [String], options: ParsedOptions) throws {
        guard let sub = positional.first else {
            throw CLIError(message: "Usage: unlirice note <add|append|get|list|search|history>")
        }
        let restPositional = Array(positional.dropFirst())

        switch sub {
        case "add", "create":
            let source = try requireSource(options)
            let title = options.flags["title"] ?? restPositional.first ?? ""
            let body = options.flags["body"] ?? (restPositional.count > 1 ? restPositional[1] : "")
            guard !title.isEmpty else { throw CLIError(message: "Missing title. Use --title \"...\"") }
            let note = try service.createNote(title: title, body: body, source: source)
            try output(note, humanReadable: "Created note \"\(note.title)\" [\(note.id)]")

        case "append":
            let source = try requireSource(options)
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: restPositional)
            let text = options.flags["text"] ?? restPositional.dropFirst().joined(separator: " ")
            guard !text.isEmpty else { throw CLIError(message: "Missing text. Use --text \"...\"") }
            let note = try service.appendToNote(id: id, text: text, source: source)
            try output(note, humanReadable: "Appended to note \"\(note.title)\" [\(note.id)]")

        case "get":
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: restPositional)
            if let note = try service.getNote(id: id) {
                try output(note, humanReadable: "# \(note.title)\nID: \(note.id)\nTags: \(note.tags.joined(separator: ", "))\n\n\(note.body)")
            } else {
                throw CLIError(message: "Note not found: \(id)")
            }

        case "list":
            let includeArchived = options.flags["include-archived"] == "true" || restPositional.contains("--include-archived")
            let notes = try service.listNotes(includeArchived: includeArchived)
            if isJSON {
                try output(notes, humanReadable: "")
            } else {
                print("Notes (\(notes.count)):")
                for n in notes {
                    let arch = n.archived ? " [Archived]" : ""
                    print("- [\(n.id)] \(n.title)\(arch)")
                }
            }

        case "search":
            let query = options.flags["query"] ?? restPositional.joined(separator: " ")
            guard !query.isEmpty else { throw CLIError(message: "Missing search query") }
            let includeArchived = options.flags["include-archived"] == "true"
            let results = try service.searchNotes(query: query, includeArchived: includeArchived)
            if isJSON {
                try output(results, humanReadable: "")
            } else {
                print("Search results for '\(query)' (\(results.count)):")
                for n in results {
                    print("- [\(n.id)] \(n.title)")
                }
            }

        case "history":
            let id = try requireUUID(options, key: "id", positionalIndex: 0, positional: restPositional)
            let events = try service.noteHistory(id: id)
            try output(events, humanReadable: events.map { "[\($0.timestamp)] \($0.kind) by \($0.source)" }.joined(separator: "\n"))

        default:
            throw CLIError(message: "Unknown note subcommand: '\(sub)'.")
        }
    }

    private func initProject(name: String, options: ParsedOptions) throws {
        // Resolve Projects folder bookmark or location
        let projectsParentURL: URL
        if let claudeURL = settings.claudeProjectsURL {
            projectsParentURL = claudeURL
        } else if let exportURL = settings.exportFolderURL {
            projectsParentURL = exportURL.deletingLastPathComponent().appendingPathComponent("Projects", isDirectory: true)
        } else {
            let defaultPath = NSString(string: "~/Documents/Projects").expandingTildeInPath
            projectsParentURL = URL(fileURLWithPath: defaultPath, isDirectory: true)
        }

        let targetDir = projectsParentURL.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default

        if fm.fileExists(atPath: targetDir.path) {
            throw CLIError(message: "Directory already exists: \(targetDir.path) — refusing to overwrite.")
        }

        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Find guardrails note body if present
        let notes = (try? service.listNotes(includeArchived: false)) ?? []
        let guardrailsBody = notes.first(where: { $0.title.lowercased() == "profile: guardrails" })?.body ?? """
        # Guardrails for \(name)

        - Always do what is easiest for the user.
        - Verify code changes before declaring success.
        - Maintain append-only notes and log history.
        """

        // Write AGENTS.md and CLAUDE.md
        let agentsContent = """
        # AGENTS.md — \(name)

        \(guardrailsBody)
        """
        try Data(agentsContent.utf8).write(to: targetDir.appendingPathComponent("AGENTS.md"))
        try Data(agentsContent.utf8).write(to: targetDir.appendingPathComponent("CLAUDE.md"))

        // Write PROJECT_NOTES.md
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let projectNotesContent = """
        # \(name) — Project Notes

        Living status doc for this project. Keep it current as you work.

        ## Handoff

        - **Status:** Planning / In Progress
        - **Task:** Initializing project structure
        - **Files touched:** AGENTS.md, CLAUDE.md, PROJECT_NOTES.md
        - **Next step:** Define initial scope and code foundation
        - **Gotchas:** None
        - **Left by:** unlirice CLI

        ## Overview

        \(name) project initialized via Unli Rice CLI.

        ## Decisions Log

        - **\(dateStr)**: Project initialized with `unlirice project init`.

        ## Session Log

        - **\(dateStr)**: Repository created and initial context files attached.
        """
        try Data(projectNotesContent.utf8).write(to: targetDir.appendingPathComponent("PROJECT_NOTES.md"))

        // Run git init
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = targetDir
        try? process.run()
        process.waitUntilExit()

        // Register Project: <Name> note in vault
        let source = options.flags["source"] ?? "unlirice-cli"
        let projectNoteBody = """
        Project folder: `\(targetDir.path)`
        Initialized: \(dateStr)

        Contains `AGENTS.md`, `CLAUDE.md`, and `PROJECT_NOTES.md`.
        """
        let projectNote = try service.createNote(title: "Project: \(name)", body: projectNoteBody, source: source)

        try output(projectNote, humanReadable: "Initialized project '\(name)' at \(targetDir.path) and registered Project note [\(projectNote.id)]")
    }

    private func requireSource(_ options: ParsedOptions) throws -> String {
        guard let source = options.flags["source"], !source.isEmpty else {
            throw CLIError(message: "--source <name> is required for mutating commands (e.g. --source antigravity).")
        }
        return source
    }

    private func requireString(_ options: ParsedOptions, key: String, positionalIndex: Int, positional: [String]) throws -> String {
        if let flagVal = options.flags[key], !flagVal.isEmpty {
            return flagVal
        }
        if positionalIndex < positional.count, !positional[positionalIndex].isEmpty {
            return positional[positionalIndex]
        }
        throw CLIError(message: "Missing argument: --\(key) <value>")
    }

    private func requireUUID(_ options: ParsedOptions, key: String, positionalIndex: Int, positional: [String]) throws -> UUID {
        let str = try requireString(options, key: key, positionalIndex: positionalIndex, positional: positional)
        guard let id = UUID(uuidString: str) else {
            throw CLIError(message: "Invalid UUID format for argument '--\(key)': \(str)")
        }
        return id
    }

    private func printUsage() {
        print("""
        unlirice CLI — Command line interface for Unli Rice persistent memory

        USAGE:
            unlirice <command> [subcommand] [options]

        COMMANDS:
            note add --title "..." --body "..." --source "..."
            note append --id <uuid> --text "..." --source "..."
            note get --id <uuid>
            note list [--include-archived] [--json]
            note search "<query>" [--include-archived] [--json]
            note history --id <uuid> [--json]

            tag --id <uuid> --tag "..." --source "..."
            untag --id <uuid> --tag "..." --source "..."
            archive --id <uuid> --reason "..." --source "..."
            unarchive --id <uuid> --source "..."

            flag --id <uuid> --reason "..." --source "..."
            reviews [--json]
            resolve --id <uuid> --flag-id <uuid> [--outcome "..."] --source "..."

            log [--limit 50] [--json]

            project init <name> [--source "..."]

        GLOBAL OPTIONS:
            --json       Output raw JSON formatted data
            --source     Identify calling agent (required on mutating commands)
        """)
    }
}

struct ParsedOptions {
    var flags: [String: String] = [:]
    var positional: [String] = []
}

func parseOptions(_ args: [String]) -> ParsedOptions {
    var opts = ParsedOptions()
    var idx = 0
    while idx < args.count {
        let arg = args[idx]
        if arg.hasPrefix("--") {
            let key = String(arg.dropFirst(2))
            if idx + 1 < args.count && !args[idx + 1].hasPrefix("--") {
                opts.flags[key] = args[idx + 1]
                idx += 2
            } else {
                opts.flags[key] = "true"
                idx += 1
            }
        } else {
            opts.positional.append(arg)
            idx += 1
        }
    }
    return opts
}

// Entrypoint Execution
let rawArgs = Array(CommandLine.arguments.dropFirst())
let isJSON = rawArgs.contains("--json")
let cleanArgs = rawArgs.filter { $0 != "--json" }

let settings = AgentSettings.load()

// Shared resolver: the scope held and the log opened must be the same folder.
let corpus = CorpusLocation.resolve(settings: settings)
let activeDataFolder: URL? = corpus.scopedFolder
defer { activeDataFolder?.stopAccessingSecurityScopedResource() }

let logURL = corpus.url
if case .defaultAfterFolderFailed(let failure) = corpus.source {
    FileHandle.standardError.write(Data(
        ("Warning: couldn't open the chosen notes folder"
         + (failure.path.map { " (\($0))" } ?? "")
         + "; using \(logURL.path) instead.\n").utf8
    ))
}
guard let store = try? EventStore(fileURL: logURL) else {
    FileHandle.standardError.write(Data("Error: Could not open event log at \(logURL.path)\n".utf8))
    exit(1)
}

let deviceIdentity = DeviceIdentity.current(inDirectory: logURL.deletingLastPathComponent())
let service = NoteService(store: store, deviceLabel: deviceIdentity.label)

let cli = UnliRiceCLI(settings: settings, logURL: logURL, service: service, isJSON: isJSON)

do {
    try cli.run(args: cleanArgs)
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit(1)
}
