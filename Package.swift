// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NetCheckerTraffic",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // Single product - import NetCheckerTraffic to get everything
        .library(
            name: "NetCheckerTraffic",
            targets: ["NetCheckerTraffic"]
        ),
    ],
    targets: [
        // Internal core target (not directly imported by users)
        .target(
            name: "NetCheckerTrafficCore",
            dependencies: [],
            path: "Sources/NetCheckerTraffic"
        ),

        // Public-facing module that includes UI and re-exports Core
        .target(
            name: "NetCheckerTraffic",
            dependencies: ["NetCheckerTrafficCore"],
            path: "Sources/NetCheckerTrafficUI"
        ),

        // Tests
        .testTarget(
            name: "NetCheckerTrafficTests",
            dependencies: ["NetCheckerTrafficCore"],
            path: "Tests/NetCheckerTrafficTests"
        ),
    ]
)
