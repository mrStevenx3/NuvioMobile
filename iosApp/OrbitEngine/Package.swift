// swift-tools-version: 6.1

import PackageDescription

// Orbit's playback engine (Steven's fork, 2026-10-25): AetherEngine with the optional components
// Orbit wants switched on. Xcode cannot set a remote package's traits reliably, so this small local
// package depends on AetherEngine with them and re-exports it (`import OrbitEngine`).
//  - TrueHDObjectAudio / DTSXObjectAudio: TrueHD Atmos and DTS:X keep their heights (rendered to
//    Apple's spatial audio, sent to the receiver as Dolby MAT).
//  - DolbyVisionStillReshaping: scrub thumbnails for Dolby Vision profile 5 sources.
let package = Package(
    name: "OrbitEngine",
    platforms: [
        .tvOS(.v18),
        .iOS(.v18),
    ],
    products: [
        .library(name: "OrbitEngine", targets: ["OrbitEngine"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            from: "7.47.0",
            traits: ["TrueHDObjectAudio", "DTSXObjectAudio", "DolbyVisionStillReshaping"]
        ),
    ],
    targets: [
        .target(
            name: "OrbitEngine",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
