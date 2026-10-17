// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Which programs may talk to the app's socket (upstream `Ipc/IpcClientVerifier.cs`): only the app's own executables,
/// from its own bundle (a bare `swift build`: the same folder), each for the sources it uses. Other programs can't use
/// the socket directly; they can run greenshot-cli, which always says "cli". The app checks the peer's code signature
/// on top (`requirement`).
public enum IPCPeerPolicy {
    public struct Program: Equatable, Sendable {
        public var name: String
        /// Where it lives in the app bundle.
        public var bundleFolder: String
        public var sources: Set<IPCSource>
    }

    /// Wave 4 adds the native messaging host and the MCP server.
    public static let programs: [Program] = [
        // A second start of the app forwards its command line
        Program(name: "GreenshotMac", bundleFolder: "Contents/MacOS", sources: [.cli]),
        // The command line tool
        Program(name: "greenshot-cli", bundleFolder: "Contents/Helpers", sources: [.cli]),
    ]

    /// The app bundle of an executable in its `Contents/MacOS` or `Contents/Helpers`; nil for a bare build.
    public static func appBundle(ofExecutable path: String) -> String? {
        let folder = (path as NSString).deletingLastPathComponent
        guard ["MacOS", "Helpers"].contains((folder as NSString).lastPathComponent) else { return nil }
        let contents = (folder as NSString).deletingLastPathComponent
        guard (contents as NSString).lastPathComponent == "Contents" else { return nil }
        let bundle = (contents as NSString).deletingLastPathComponent
        return bundle.lowercased().hasSuffix(".app") ? bundle : nil
    }

    /// Nil when the program at `peerExecutable` may connect as `source` to the app running from `hostExecutable`, else
    /// the reason. Both paths with symlinks resolved.
    public static func check(peerExecutable: String, source: IPCSource, hostExecutable: String) -> String? {
        let name = (peerExecutable as NSString).lastPathComponent
        let refusal = "Only Greenshot's own programs may connect, not '\(peerExecutable)'."
        guard let program = programs.first(where: { $0.name == name }) else { return refusal }
        let expected: String
        if let bundle = appBundle(ofExecutable: hostExecutable) {
            expected = ((bundle as NSString).appendingPathComponent(program.bundleFolder) as NSString).appendingPathComponent(name)
        } else {
            expected = ((hostExecutable as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
        }
        guard (peerExecutable as NSString).standardizingPath == (expected as NSString).standardizingPath else { return refusal }
        guard program.sources.contains(source) else { return "\(name) may not connect as '\(source.rawValue)'." }
        return nil
    }

    /// The code requirement a peer's signature must meet: the app's Team ID, or for a self-signed certificate (e.g.
    /// "Greenshot Dev") the same leaf certificate; nil for an ad hoc or unsigned app, which has no anchor to compare.
    public static func requirement(teamID: String?, leafCertificateSHA1: String?) -> String? {
        if let teamID, !teamID.isEmpty, teamID.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        }
        if let hash = leafCertificateSHA1, !hash.isEmpty, hash.allSatisfy(\.isHexDigit) {
            return "certificate leaf = H\"\(hash.lowercased())\""
        }
        return nil
    }
}
