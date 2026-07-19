// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SecondBrain",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SecondBrainCore", targets: ["SecondBrainCore"]),
        .executable(name: "secondbrain-mcp", targets: ["secondbrain-mcp"])
    ],
    targets: [
        .target(name: "SecondBrainCore"),
        .executableTarget(
            name: "secondbrain-mcp",
            dependencies: ["SecondBrainCore"]
        ),
        .testTarget(
            name: "SecondBrainCoreTests",
            dependencies: ["SecondBrainCore"]
        )
    ]
)
