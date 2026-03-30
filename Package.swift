// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OverworkTracker",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OverworkTracker",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "OverworkTracker",
            resources: [],
            linkerSettings: [
                .unsafeFlags(["-framework", "Cocoa"]),
                .unsafeFlags(["-framework", "ApplicationServices"])
            ]
        )
    ]
)
