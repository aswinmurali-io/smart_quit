// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lingerer",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LingererCore"),
        .executableTarget(name: "Lingerer", dependencies: ["LingererCore"]),
        .testTarget(name: "LingererCoreTests", dependencies: ["LingererCore"]),
    ]
)
