// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "HyprOSX",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyprOSX", targets: ["HyprOSX"]),
        .executable(name: "hyprctl", targets: ["hyprctl"]),
    ],
    targets: [
        .target(name: "HyprCore", swiftSettings: v5),
        .executableTarget(name: "HyprOSX", dependencies: ["HyprCore"], swiftSettings: v5),
        .executableTarget(name: "hyprctl", swiftSettings: v5),
        .testTarget(name: "HyprCoreTests", dependencies: ["HyprCore"], swiftSettings: v5),
    ]
)
