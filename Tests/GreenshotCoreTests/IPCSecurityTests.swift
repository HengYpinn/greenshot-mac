// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation
import Testing
@testable import GreenshotCore

/// Upstream `SecurityDispatcher_PathSanitizer_*`, `SecurityDispatcher_OpenFile_*`.
struct IPCPathValidatorTests {
    private let allowed: Set<String> = ["png", "jpg", "jpeg", "greenshot"]

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gs-path-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func message(_ raw: String, cwd: String?) -> String? {
        if case .failure(let failure) = IPCPathValidator.resolve(raw, cwd: cwd, allowedExtensions: allowed) { return failure.message }
        return nil
    }

    @Test func relativePathsAreTakenFromTheCallersFolder() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([1]).write(to: folder.appendingPathComponent("shot.png"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let resolved = try IPCPathValidator.resolve("sub/../shot.png", cwd: folder.path, allowedExtensions: allowed).get()
        #expect(resolved.lastPathComponent == "shot.png")
        #expect(!resolved.path.contains(".."))
        let absolute = try IPCPathValidator.resolve(folder.appendingPathComponent("shot.png").path, cwd: nil, allowedExtensions: allowed).get()
        #expect(absolute.lastPathComponent == "shot.png")
    }

    @Test func unicodeFileNamesAreAccepted() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["Bildschirmfoto Größe.PNG", "スクリーン 📸.jpg", "file.greenshot"] {
            try Data([1]).write(to: folder.appendingPathComponent(name))
            let result = IPCPathValidator.resolve(name, cwd: folder.path, allowedExtensions: allowed)
            #expect((try? result.get()) != nil)
        }
    }

    @Test(arguments: ["a\u{0}.png", "a\nb.png", "a\u{7F}.png", "a\u{202E}gnp.exe", "a\u{200B}.png", "a\u{2066}.png", "\u{FEFF}a.png"])
    func controlAndFormattingCharactersAreRejected(raw: String) {
        let text = message(raw, cwd: "/tmp") ?? ""
        #expect(text.contains("characters"))
    }

    @Test func emptyRelativeWithoutFolderMissingAndWrongTypeAreRejected() throws {
        #expect(message("  ", cwd: "/tmp") == "Path is empty or whitespace.")
        #expect(message("a.png", cwd: nil)?.contains("working directory") == true)
        #expect(message("/nowhere/\(UUID().uuidString).png", cwd: nil)?.contains("does not exist") == true)
        #expect(message("/tmp/run.sh", cwd: nil)?.contains("not permitted") == true)
        #expect(message("/tmp/noextension", cwd: nil)?.contains("not permitted") == true)
        #expect(message("/dev/null", cwd: nil)?.contains("not permitted") == true)
    }

    @Test func foldersAndFifosAreNotFiles() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("dir.png"), withIntermediateDirectories: true)
        #expect(message("dir.png", cwd: folder.path)?.contains("Not a regular file") == true)
        let fifo = folder.appendingPathComponent("pipe.png").path
        #expect(mkfifo(fifo, 0o600) == 0)
        #expect(message("pipe.png", cwd: folder.path)?.contains("Not a regular file") == true)
    }

    @Test func editorExtensionsComeFromImageIO() {
        let extensions = IPCPathValidator.editorImageExtensions
        for name in ["png", "jpg", "jpeg", "tiff", "gif", "heic", "greenshot"] {
            #expect(extensions.contains(name))
        }
        #expect(!extensions.contains("exe"))
        #expect(!extensions.contains("sh"))
    }
}

/// Upstream `IpcClientVerifier.IsAllowed`.
struct IPCPeerPolicyTests {
    private let host = "/Applications/Greenshot for Mac (Community).app/Contents/MacOS/GreenshotMac"

    @Test func ownProgramsInTheirPlaces() {
        #expect(IPCPeerPolicy.check(peerExecutable: "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-cli",
                                    source: .cli, hostExecutable: host) == nil)
        #expect(IPCPeerPolicy.check(peerExecutable: host, source: .cli, hostExecutable: host) == nil)
    }

    @Test func otherProgramsPlacesAndBundlesAreRefused() {
        let refusals = [
            "/usr/bin/nc",
            "/Applications/Greenshot for Mac (Community).app/Contents/MacOS/greenshot-cli",
            "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/GreenshotMac",
            "/Users/me/Downloads/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-cli",
            "/usr/local/bin/greenshot-cli",
        ].compactMap { IPCPeerPolicy.check(peerExecutable: $0, source: .cli, hostExecutable: host) }
        #expect(refusals.count == 5)
        #expect(refusals.allSatisfy { $0.hasPrefix("Only Greenshot's own programs may connect") })
    }

    @Test func programsOnlyUseTheirSources() {
        let cli = "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-cli"
        #expect(IPCPeerPolicy.check(peerExecutable: cli, source: .nativeMessaging, hostExecutable: host)
            == "greenshot-cli may not connect as 'native_messaging'.")
    }

    @Test func bareBuildUsesTheSameFolder() {
        let devHost = "/src/.build/debug/GreenshotMac"
        #expect(IPCPeerPolicy.check(peerExecutable: "/src/.build/debug/greenshot-cli", source: .cli, hostExecutable: devHost) == nil)
        #expect(IPCPeerPolicy.check(peerExecutable: "/src/.build/release/greenshot-cli", source: .cli, hostExecutable: devHost) != nil)
    }

    @Test func appBundleOfAnExecutable() {
        #expect(IPCPeerPolicy.appBundle(ofExecutable: host) == "/Applications/Greenshot for Mac (Community).app")
        #expect(IPCPeerPolicy.appBundle(ofExecutable: "/X.app/Contents/Helpers/greenshot-cli") == "/X.app")
        #expect(IPCPeerPolicy.appBundle(ofExecutable: "/src/.build/debug/GreenshotMac") == nil)
        #expect(IPCPeerPolicy.appBundle(ofExecutable: "/X/Contents/MacOS/GreenshotMac") == nil)
    }

    @Test func requirementFollowsTheAppsOwnSignature() {
        #expect(IPCPeerPolicy.requirement(teamID: "ABCDE12345", leafCertificateSHA1: "ff")
            == "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\"")
        #expect(IPCPeerPolicy.requirement(teamID: nil, leafCertificateSHA1: "AB12") == "certificate leaf = H\"ab12\"")
        #expect(IPCPeerPolicy.requirement(teamID: nil, leafCertificateSHA1: nil) == nil)
        #expect(IPCPeerPolicy.requirement(teamID: "a\" or 1", leafCertificateSHA1: nil) == nil)
    }
}

struct IPCEndpointTests {
    private let support = URL(fileURLWithPath: "/Users/me/Library/Application Support")

    @Test func socketPerBundleIdentifierWithDevSuffix() {
        let app = IPCEndpoint(bundleIdentifier: "io.example.Shot", appBundlePath: "/Applications/Shot.app",
                              temporaryFolder: "/var/folders/ab/cd/T/", applicationSupport: support)
        #expect(app.socketPath == "/var/folders/ab/cd/T/io.example.Shot.ipc")
        #expect(app.instanceLockURL.path == "/Users/me/Library/Application Support/io.example.Shot/instance.lock")
        let dev = IPCEndpoint(bundleIdentifier: nil, appBundlePath: nil, temporaryFolder: "/var/folders/ab/cd/T", applicationSupport: support)
        #expect(dev.bundleIdentifier == IPCEndpoint.defaultBundleIdentifier)
        #expect(dev.socketPath == "/var/folders/ab/cd/T/io.github.greenshot-mac.GreenshotMac-dev.ipc")
        #expect(dev.instanceLockURL.lastPathComponent == "instance-dev.lock")
        #expect(dev.coldStartLockURL.lastPathComponent == "coldstart-dev.lock")
    }

    @Test func longPathsGetAShortHashedName() {
        let folder = "/var/folders/" + String(repeating: "x", count: 60)
        let long = IPCEndpoint.socketPath(bundleIdentifier: "io.example.a.very.long.bundle.identifier.Shot", development: false,
                                          temporaryFolder: folder)
        #expect(long.utf8.count <= IPCSocket.maximumPathLength)
        #expect(long.contains("/gsmac-"))
        let again = IPCEndpoint.socketPath(bundleIdentifier: "io.example.a.very.long.bundle.identifier.Shot", development: false,
                                           temporaryFolder: folder)
        #expect(again == long)
        let dev = IPCEndpoint.socketPath(bundleIdentifier: "io.example.a.very.long.bundle.identifier.Shot", development: true,
                                         temporaryFolder: folder)
        #expect(dev != long)
    }

    @Test func realUserTemporaryFolderIsShortEnough() {
        let path = IPCEndpoint.socketPath(bundleIdentifier: IPCEndpoint.defaultBundleIdentifier, development: false,
                                          temporaryFolder: IPCEndpoint.userTemporaryFolder)
        #expect(path.utf8.count <= IPCSocket.maximumPathLength)
        #expect(path.hasPrefix("/"))
    }

    @Test func endpointOfAnExecutableReadsItsBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gs-bundle-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Shot.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Helpers"), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": "io.example.Shot"]
        #expect(info.write(to: contents.appendingPathComponent("Info.plist"), atomically: true))
        let endpoint = IPCEndpoint.forExecutable(contents.appendingPathComponent("Helpers/greenshot-cli").path,
                                                 temporaryFolder: "/tmp/T", applicationSupport: support)
        #expect(endpoint.bundleIdentifier == "io.example.Shot")
        #expect(!endpoint.isDevelopmentBuild)
        #expect(endpoint.socketPath == "/tmp/T/io.example.Shot.ipc")
        let bare = IPCEndpoint.forExecutable("/src/.build/debug/greenshot-cli", temporaryFolder: "/tmp/T", applicationSupport: support)
        #expect(bare.isDevelopmentBuild)
    }

    @Test func instanceLockIsExclusive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gs-lock-\(UUID().uuidString.prefix(8))/instance.lock")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        guard case .acquired(let first) = IPCFileLock.acquire(url) else {
            Issue.record("The first lock wasn't acquired")
            return
        }
        if case .heldByOther(let pid) = IPCFileLock.acquire(url) {
            #expect(pid == getpid())
        } else {
            Issue.record("A second lock was acquired while the first was held")
        }
        #expect(IPCFileLock.wait(url, timeout: 0.1) == nil)
        first.release()
        let second = IPCFileLock.wait(url, timeout: 1)
        #expect(second != nil)
        second?.release()
    }
}
