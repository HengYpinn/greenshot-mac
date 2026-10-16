// swift-tools-version:6.0
// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "GreenshotMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GreenshotMac", targets: ["GreenshotMac"]),
    ],
    targets: [
        // Platform logic without windows: filename patterns, settings, the annotation model and its renderer.
        .target(name: "GreenshotCore"),
        // The menu bar app: hotkeys, capture overlay, editor window, settings window.
        .executableTarget(name: "GreenshotMac", dependencies: ["GreenshotCore"]),
        .testTarget(name: "GreenshotCoreTests", dependencies: ["GreenshotCore"]),
    ],
    swiftLanguageModes: [.v5]
)
