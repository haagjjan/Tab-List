// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TabListCore",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "TabListCore", targets: ["TabListCore"]),
        .executable(
            name: "TabListCoreBenchmarks",
            targets: ["TabListCoreBenchmarks"]
        ),
        .executable(name: "TabList", targets: ["TabList"]),
    ],
    dependencies: [
        // Command Line Tools 26.2 ships an incomplete Testing.framework
        // overlay. Pin the matching upstream release for deterministic
        // command-line tests; Xcode uses its built-in Swift Testing runtime.
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            revision: "48a471ab313e858258ab0b9b0bf2cea55a50cefb"
        ),
    ],
    targets: [
        .target(
            name: "TabListCore",
            path: "Sources/TabListCore"
        ),
        .executableTarget(
            name: "TabListCoreBenchmarks",
            dependencies: ["TabListCore"],
            path: "Sources/TabListCoreBenchmarks"
        ),
        .executableTarget(
            name: "TabList",
            dependencies: ["TabListCore"],
            path: "Sources/TabList"
        ),
        .testTarget(
            name: "TabListCoreTests",
            dependencies: [
                "TabListCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/TabListCoreTests"
        ),
        .testTarget(
            name: "TabListTests",
            dependencies: [
                "TabList",
                "TabListCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/TabListTests"
        ),
    ]
)
