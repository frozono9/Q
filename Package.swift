// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Q",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Q", targets: ["Q"])
    ],
    targets: [
        .target(
            name: "QCore",
            path: "Sources/Q",
            sources: ["Models", "Device"]
        ),
        .executableTarget(
            name: "Q",
            dependencies: ["QCore"],
            path: "Sources/Q",
            sources: ["App", "UI"]
        ),
        .testTarget(
            name: "QTests",
            dependencies: ["QCore"],
            path: "Tests/QTests"
        )
    ]
)
