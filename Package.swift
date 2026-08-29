// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartQuit",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "SmartQuitCore"),
        .executableTarget(name: "SmartQuit", dependencies: ["SmartQuitCore"]),
        .testTarget(name: "SmartQuitCoreTests", dependencies: ["SmartQuitCore"]),
    ]
)
