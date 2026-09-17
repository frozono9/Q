// swift-tools-version: 6.0

import PackageDescription

// Keep the existing Mac sources and module name intact. Other hosts compile
// the same models and protocol without the Apple-specific device adapters.
#if os(macOS)
let coreExcludes = ["App", "Integrations", "UI"]
let testExcludes: [String] = []
let appProducts: [Product] = [
    .executable(name: "Q", targets: ["Q"]),
    .executable(name: "QDeviceWatcher", targets: ["QDeviceWatcher"]),
    .executable(name: "QClaudeHook", targets: ["QClaudeHook"])
]
let appTargets: [Target] = [
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
    )
]
#else
let coreExcludes = [
    "App", "Integrations", "UI",
    "Device/SerialQDevice.swift", "Device/VirtualQDevice.swift"
]
// These three tests exercise the Combine-based Mac virtual device. All model,
// resolver and protocol tests still run unchanged on every supported host.
let testExcludes = ["VirtualQDeviceTests.swift"]
let appProducts: [Product] = []
let appTargets: [Target] = []
#endif

let package = Package(
    name: "Q",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QCore", targets: ["QCore"])
    ] + appProducts,
    targets: [
        .target(
            name: "QCore",
            path: "Sources/Q",
            exclude: coreExcludes,
            sources: ["Models", "Device"]
        ),
        .testTarget(
            name: "QTests",
            dependencies: ["QCore"],
            path: "Tests/QTests",
            exclude: testExcludes
        )
    ] + appTargets
)
