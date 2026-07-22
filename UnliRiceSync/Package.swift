// swift-tools-version: 5.10
import PackageDescription

// A separate package, not a target added to the root manifest, and that's
// deliberate. SwiftData's CloudKit backing needs macOS 14; the root package
// was moved back down to macOS 13 on purpose after MLX forced it up (see
// PROJECT_NOTES.md, "Removing the on-device model") and nothing here should
// re-impose that floor on UnliRiceCore, unlirice-mcp, unlirice-agent, or the
// test suite — none of which need to know sync exists. Only the GUI app
// target opts in, by adding this package as an Xcode dependency alongside the
// root one. See UnliRiceSync/README.md for the exact Xcode steps; none of
// this has been built or run yet — there is no macOS/Xcode toolchain in the
// environment that wrote it.
let package = Package(
    name: "UnliRiceSync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UnliRiceSync", targets: ["UnliRiceSync"])
    ],
    dependencies: [
        // One-directional: this package depends on the root package's
        // UnliRiceCore product. The root package's own manifest is untouched
        // and does not depend back on this one — SwiftPM does not allow
        // package dependency cycles, and this is also what keeps
        // `swift build`/`swift test` at the repo root exactly as they were.
        .package(path: "..")
    ],
    targets: [
        .target(
            name: "UnliRiceSync",
            dependencies: [
                .product(name: "UnliRiceCore", package: "UnliRice")
            ]
        ),
        .testTarget(
            name: "UnliRiceSyncTests",
            dependencies: ["UnliRiceSync"]
        )
    ]
)
