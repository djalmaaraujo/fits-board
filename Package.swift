// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Fits",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FitsCore", targets: ["FitsCore"]),
        .executable(name: "FitsBoard", targets: ["FitsBoard"])
    ],
    targets: [
        .target(name: "FitsCore"),
        .executableTarget(
            name: "FitsBoard",
            dependencies: ["FitsCore"]
        ),
        .testTarget(
            name: "FitsCoreTests",
            dependencies: ["FitsCore"]
        )
    ]
)
