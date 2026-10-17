// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

// greenshot-native-host: the browser extension's native messaging host (upstream src/greenshot-proxy, main_proxy.c), in
// the app bundle (Contents/Helpers). Chrome, Edge or Firefox start it for the extension; it relays the extension's
// messages to the running app (BrowserNativeHost). stdout belongs to the browser: nothing else is ever written there.

import Darwin
import Foundation
import GreenshotCore

signal(SIGPIPE, SIG_IGN)
let endpoint = IPCEndpoint.forExecutable(IPCEndpoint.currentExecutablePath)

var version: String {
    guard let bundle = endpoint.appBundlePath,
          let value = IPCEndpoint.infoDictionary(ofBundle: bundle)?["CFBundleShortVersionString"] as? String else { return "development build" }
    return value
}

guard let origin = BrowserNativeHost.extensionOrigin(arguments: CommandLine.arguments) else {
    let usage = """
        greenshot-native-host connects the Greenshot for Mac (Community) browser extension with the app. Chrome, Edge and
        Firefox start it themselves; install it in Settings › Expert › Browser extension.

        """
    FileHandle.standardError.write(Data(usage.utf8))
    exit(CommandLine.arguments.count > 1 ? IPCExitCode.usage : IPCExitCode.ok)
}
exit(BrowserNativeHost.run(origin: origin, socketPath: endpoint.socketPath, clientVersion: version))
