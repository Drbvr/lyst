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
