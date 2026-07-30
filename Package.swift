// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TabListCore",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "TabListCore", targets: ["TabListCore"]),
    ],
    targets: [
        .target(
            name: "TabListCore",
            path: "Sources/TabListCore"
        ),
        .testTarget(
            name: "TabListCoreTests",
            dependencies: ["TabListCore"],
            path: "Tests/TabListCoreTests"
        ),
    ]
)
