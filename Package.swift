// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Q",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Q", targets: ["Q"]),
        .executable(name: "QDeviceWatcher", targets: ["QDeviceWatcher"]),
        .executable(name: "QClaudeHook", targets: ["QClaudeHook"])
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
            sources: ["App", "Integrations", "UI"]
        ),
        .executableTarget(
            name: "QDeviceWatcher",
            path: "Sources/QDeviceWatcher"
        ),
        .executableTarget(
            name: "QClaudeHook",
            path: "Sources/QClaudeHook"
        ),
        .testTarget(
            name: "QTests",
            dependencies: ["QCore"],
            path: "Tests/QTests"
        )
    ]
)
