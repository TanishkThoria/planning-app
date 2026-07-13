// swift-tools-version:5.9
import PackageDescription

// A tiny Swift Package that exposes Chronos's *platform-agnostic* logic so it
// can be unit-tested on Linux (and in CI) without the Apple UI/EventKit SDKs.
//
// The full app is an Xcode project (Chronos.xcodeproj) built on macOS; this
// package only compiles the Foundation-only pieces. Xcode ignores this file.
//
// Today that's the date utilities. As more logic is decoupled from SwiftUI,
// additional files can be added to the ChronosCore target's `sources`.
let package = Package(
    name: "ChronosCore",
    products: [
        .library(name: "ChronosCore", targets: ["ChronosCore"]),
    ],
    targets: [
        .target(
            name: "ChronosCore",
            path: "Chronos/Utilities",
            sources: ["DateUtils.swift"]
        ),
        .testTarget(
            name: "ChronosCoreTests",
            dependencies: ["ChronosCore"],
            path: "Tests/ChronosCoreTests"
        ),
    ]
)
