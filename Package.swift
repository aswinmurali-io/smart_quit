// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Aswin Murali
// SPDX-License-Identifier: GPL-3.0-only

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
