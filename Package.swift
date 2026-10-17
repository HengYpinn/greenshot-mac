// swift-tools-version:6.0
// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "GreenshotMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GreenshotMac", targets: ["GreenshotMac"]),
        .executable(name: "greenshot-cli", targets: ["greenshot-cli"]),
        .executable(name: "greenshot-mcp", targets: ["greenshot-mcp"]),
        .executable(name: "greenshot-native-host", targets: ["greenshot-native-host"]),
    ],
    targets: [
        // Platform logic without windows: filename patterns, settings, the annotation model and its renderer.
        .target(name: "GreenshotCore"),
        // The menu bar app: hotkeys, capture overlay, editor window, settings window.
        .executableTarget(name: "GreenshotMac", dependencies: ["GreenshotCore"]),
        // The command line tool, bundled into the app (Contents/Helpers): talks to the running app (upstream greenshot-cli).
        .executableTarget(name: "greenshot-cli", dependencies: ["GreenshotCore"]),
        // The MCP server for AI tools, bundled into the app (Contents/Helpers): talks to the running app (upstream greenshot-mcp).
        .executableTarget(name: "greenshot-mcp", dependencies: ["GreenshotCore"]),
        // The browser extension's native messaging host, bundled into the app (Contents/Helpers) (upstream greenshot-proxy).
        .executableTarget(name: "greenshot-native-host", dependencies: ["GreenshotCore"]),
        .testTarget(name: "GreenshotCoreTests", dependencies: ["GreenshotCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v5]
)
