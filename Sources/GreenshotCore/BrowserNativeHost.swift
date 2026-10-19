// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// The browser extension's native messaging host, greenshot-native-host (upstream `src/greenshot-proxy/main_proxy.c`,
/// `extension_relay.c`). A browser starts it with the extension's origin and talks to it on stdin/stdout in frames of a
/// 4-byte little-endian length and JSON, the same framing as the app's socket. The host announces the connection as
/// `native_messaging` with that origin and then relays the frames unchanged both ways; the app checks the origin and
/// handles the messages. It never starts the app (upstream ADR 003): when the app isn't running it tells the extension,
/// which tries again later.
public enum BrowserNativeHost {
    /// The answer when the app isn't running (upstream `OFFLINE_JSON`).
    public static let offlineReply = Data(#"{"status":"unavailable","greenshot_running":false,"retry":true}"#.utf8)
    public static let clientName = "greenshot-native-host"

    /// The extension's origin when a browser started the host (upstream `GetExtensionOrigin`); `arguments` with the
    /// program first, like `CommandLine.arguments`. Only the exact shapes browsers use count:
    /// Chrome, Edge, Chromium: `chrome-extension://<id>/` (Windows adds `--parent-window=<n>`);
    /// Firefox: `<path of the host manifest>.json <add-on id>`.
    public static func extensionOrigin(arguments: [String]) -> String? {
        let arguments = Array(arguments.dropFirst())
        if let first = arguments.first, first.lowercased().hasPrefix("chrome-extension://") { return first }
        if arguments.count == 2, arguments[0].lowercased().hasSuffix(".json"),
           arguments[1].contains("@") || arguments[1].hasPrefix("{") {
            return arguments[1]
        }
        return nil
    }

    /// Connects to the app at `socketPath`, sends HELLO and relays until the browser or the app closes its end. Returns
    /// the exit code (0 also when the app isn't running: the extension got the offline answer).
    /// `isApp` checks the program on the other end of the socket (greenshot-native-host: the GreenshotMac of its own
    /// bundle, `IPCAppLauncher.isAppPeer`). Another program of the user can listen on the app's socket while the app
    /// isn't running; it must not get the tab pictures and addresses the extension sends, nor set the extension's
    /// options with its HANDSHAKE answer, so a stranger gets nothing and the extension hears that the app is offline.
    public static func run(origin: String, socketPath: String, clientVersion: String,
                           input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO,
                           isApp: (Int32) -> Bool = { _ in true }) -> Int32 {
        // A browser that went away must not kill the host with SIGPIPE
        _ = fcntl(output, F_SETNOSIGPIPE, 1)
        guard let socket = try? IPCSocket.connect(to: socketPath) else {
            try? IPCFrameIO.writeFrame(output, offlineReply)
            return IPCExitCode.ok
        }
        guard isApp(socket) else {
            close(socket)
            FileHandle.standardError.write(Data("The program listening on Greenshot for Mac's socket isn't Greenshot for Mac, so nothing was sent to it.\n".utf8))
            try? IPCFrameIO.writeFrame(output, offlineReply)
            return IPCExitCode.ok
        }
        IPCSocket.setNoSigPipe(socket)
        let hello = IPCEnvelope.hello(source: .nativeMessaging, replyFormat: .json, client: clientName,
                                      clientVersion: clientVersion, origin: origin)
        do {
            try IPCFrameIO.writeFrame(socket, IPCJSON.data(hello.jsonObject))
        } catch {
            close(socket)
            return IPCExitCode.failure
        }
        BrowserRelay(input: input, output: output, socket: socket).run()
        return IPCExitCode.ok
    }
}

/// Two copying threads (upstream `RunExtensionRelay`): browser → app and app → browser. Either end closing ends both:
/// the socket is shut down for the reader of the app's side, a wake pipe ends the reader of the browser's side (a thread
/// blocked in `read` on a pipe can't be woken otherwise).
final class BrowserRelay: @unchecked Sendable {
    private let input: Int32
    private let output: Int32
    private let socket: Int32
    private var wake: [Int32] = [-1, -1]
    private let finished = DispatchSemaphore(value: 0)

    init(input: Int32, output: Int32, socket: Int32) {
        self.input = input
        self.output = output
        self.socket = socket
    }

    /// Returns when one side ended and the other followed, or after `linger` (then the process ends anyway).
    func run(linger: TimeInterval = 1) {
        guard pipe(&wake) == 0 else {
            close(socket)
            return
        }
        let toApp = Thread { [self] in
            browserToApp()
            finished.signal()
        }
        toApp.name = "Browser to app"
        let toBrowser = Thread { [self] in
            appToBrowser()
            finished.signal()
        }
        toBrowser.name = "App to browser"
        toApp.start()
        toBrowser.start()

        finished.wait()
        Darwin.shutdown(socket, SHUT_RDWR)
        var byte: UInt8 = 1
        _ = write(wake[1], &byte, 1)
        guard finished.wait(timeout: .now() + linger) == .success else { return }
        close(socket)
        close(wake[0])
        close(wake[1])
    }

    private func browserToApp() {
        while waitForInput() {
            guard let frame = try? IPCFrameIO.readFrame(input, minimum: IPCFrame.minimumJSONLength),
                  (try? IPCFrameIO.writeFrame(socket, frame)) != nil else { break }
        }
        // The browser closed the port (or sent nonsense): the app sees the connection end
        Darwin.shutdown(socket, SHUT_RDWR)
    }

    private func appToBrowser() {
        while let frame = try? IPCFrameIO.readFrame(socket, minimum: IPCFrame.minimumJSONLength),
              (try? IPCFrameIO.writeFrame(output, frame)) != nil {}
    }

    /// True when the browser sent something (or closed stdin, which the read then sees); false when woken to stop.
    private func waitForInput() -> Bool {
        while true {
            var fds = [pollfd(fd: input, events: Int16(POLLIN), revents: 0), pollfd(fd: wake[0], events: Int16(POLLIN), revents: 0)]
            let ready = poll(&fds, 2, -1)
            if ready < 0 {
                if errno == EINTR { continue }
                return false
            }
            if fds[1].revents != 0 { return false }
            if fds[0].revents != 0 { return true }
        }
    }
}
