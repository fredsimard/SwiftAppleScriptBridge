// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftAppleScriptBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftAppleScriptBridge",
            targets: ["SwiftAppleScriptBridge"]
        )
    ],
    targets: [
        .target(
            name: "SwiftAppleScriptBridge",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftAppleScriptBridgeTests",
            dependencies: ["SwiftAppleScriptBridge"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
