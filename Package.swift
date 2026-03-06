// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ListApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Core",
            targets: ["Core"]),
    ],
    targets: [
        .executableTarget(
            name: "ListApp",
            dependencies: ["Core"],
            path: "ListApp",
            exclude: ["Info.plist", "README.md"]
        ),
        .target(
            name: "Core",
            path: "Sources/Core"),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/CoreTests"),
    ]
)
