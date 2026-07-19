// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UnliRice",
    // macOS 14 is MLX's floor. Only UnliRiceMLX needs it, but SPM platforms are
    // package-wide, so the whole package moves up with it.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UnliRiceCore", targets: ["UnliRiceCore"]),
        .library(name: "UnliRiceMLX", targets: ["UnliRiceMLX"]),
        .executable(name: "unlirice-mcp", targets: ["unlirice-mcp"]),
        .executable(name: "janitor-calibrate", targets: ["janitor-calibrate"]),
        .executable(name: "UnliRice", targets: ["UnliRice"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.29.1")
    ],
    targets: [
        // Stays dependency-free on purpose — the engine, the janitor's rules and
        // its safety boundary all live here and must be testable without a model.
        .target(name: "UnliRiceCore"),

        // The MLX seam, deliberately a separate target: nothing in the core, the
        // MCP server, or the test suite pulls MLX in, so `swift test` stays fast
        // and the safety-critical code keeps building on a machine with no model.
        .target(
            name: "UnliRiceMLX",
            dependencies: [
                "UnliRiceCore",
                .product(name: "MLXEmbedders", package: "mlx-swift-examples"),
                // The chat panel's model. A separate library from MLXEmbedders —
                // one embeds, this one generates — but both stay in this one
                // target rather than a third, since both are "the MLX seam" and
                // neither is reachable from UnliRiceCore or unlirice-mcp either
                // way.
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples")
            ]
        ),
        // Read-only dry-run tool: where the duplicate thresholds come from.
        .executableTarget(
            name: "janitor-calibrate",
            dependencies: ["UnliRiceCore", "UnliRiceMLX"]
        ),
        .executableTarget(
            name: "unlirice-mcp",
            dependencies: ["UnliRiceCore"]
        ),
        .executableTarget(
            name: "UnliRice",
            dependencies: ["UnliRiceCore", "UnliRiceMLX"]
        ),
        .testTarget(
            name: "UnliRiceCoreTests",
            dependencies: ["UnliRiceCore"]
        )
    ]
)
