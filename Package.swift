// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// ListApp depends on SwiftUI/UIKit and only builds on Apple platforms.
// Core and CoreTests are pure Foundation/XCTest and run on Linux for cheap CI.
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let platformSpecificTargets: [Target] = [
    .executableTarget(
        name: "ListApp",
        dependencies: ["Core"],
        path: "ListApp",
        exclude: ["Info.plist", "README.md"]
    ),
]
#else
let platformSpecificTargets: [Target] = []
#endif

let package = Package(
    name: "ListApp",
    // Linux CI uses Swift 5.10, whose PackageDescription tops out at .v17.
    // The Xcode project's IPHONEOS_DEPLOYMENT_TARGET=26.0 is the authoritative
    // deployment target for the app; this value is only the SPM floor.
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]),
    ],
    targets: [
        .target(
            name: "Core",
            path: "Sources/Core"),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"),
    ] + platformSpecificTargets
)
