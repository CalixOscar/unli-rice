// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UnliRice",
    // Back to macOS 13. The package sat on 14 only because that was MLX's floor
    // and SPM platforms are package-wide — see PROJECT_NOTES.md for why the
    // on-device model was removed.
    // iOS 26 is the floor for `SpeechAnalyzer`/`SpeechTranscriber`, which the
    // capture app depends on — the legacy `SFSpeechRecognizer` ends a session on
    // a pause, the behaviour a dictation app exists to avoid. Adding a second
    // platform does not move the macOS floor; these are independent.
    // `.v26` needs swift-tools-version 6; the string form is the equivalent on
    // 5.10, and bumping the tools version would change concurrency defaults for
    // every target — not something to do as a side effect of adding a platform.
    platforms: [.macOS(.v13), .iOS("26.0")],
    products: [
        .library(name: "UnliRiceCore", targets: ["UnliRiceCore"]),
        .executable(name: "unlirice-mcp", targets: ["unlirice-mcp"]),
        .executable(name: "janitor-calibrate", targets: ["janitor-calibrate"]),
        .executable(name: "unlirice-agent", targets: ["unlirice-agent"]),
        .executable(name: "UnliRice", targets: ["UnliRice"])
    ],
    // No external dependencies, on purpose. The whole package now builds and
    // runs under plain `swift build` — no xcodebuild, no Metal shader
    // compilation, no `Scripts/mlx-run`.
    targets: [
        // The engine, the janitor's rules and its safety boundary. Was already
        // dependency-free; now the rest of the package is too.
        .target(name: "UnliRiceCore"),

        // The edge: the handful of things that need to ask macOS a question
        // (IOKit for power, CoreGraphics for idle time, launchd for background
        // execution). Kept out of the core deliberately — that's the layer
        // unlirice-mcp and the whole test suite link, and `RoutineScheduler`
        // stays a pure function over a `MachineState` someone else read.
        // Shared by the GUI and the background agent so the two can't disagree
        // about whether this Mac is plugged in.
        .target(name: "UnliRiceHost", dependencies: ["UnliRiceCore"]),

        // Read-only dry-run tool: where the duplicate thresholds come from.
        .executableTarget(
            name: "janitor-calibrate",
            dependencies: ["UnliRiceCore"]
        ),
        .executableTarget(
            name: "unlirice-mcp",
            dependencies: ["UnliRiceCore"]
        ),
        // The routines, with the window closed. launchd runs this; it does one
        // tick and exits.
        .executableTarget(
            name: "unlirice-agent",
            dependencies: ["UnliRiceCore", "UnliRiceHost"]
        ),
        .executableTarget(
            name: "UnliRice",
            dependencies: ["UnliRiceCore", "UnliRiceHost"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "UnliRiceCoreTests",
            dependencies: ["UnliRiceCore", "UnliRiceHost"]
        )
    ]
)
