// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuietTerm",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "QuietTermCore", targets: ["QuietTermCore"]),
        .executable(name: "quietterm-dev", targets: ["QuietTermDevCLI"])
    ],
    targets: [
        .target(name: "QuietTermCore"),
        .executableTarget(
            name: "QuietTermDevCLI",
            dependencies: ["QuietTermCore"]
        ),
        .testTarget(
            name: "QuietTermCoreTests",
            dependencies: ["QuietTermCore"]
        )
    ]
)
