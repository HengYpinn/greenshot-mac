// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

// The commands of the AppleScript dictionary (Resources/GreenshotMac.sdef, Mac only), e.g.
// `tell application "Greenshot for Mac (Community)" to capture full screen`. Each runs the same command as
// greenshot-cli, with the source "applescript". The Objective-C names are the dictionary's `cocoa class` names.

/// Runs the command's request and tells AppleScript how it went.
class GreenshotScriptCommand: NSScriptCommand {
    /// The request; nil with `scriptErrorString` set when the arguments are wrong.
    func makeEnvelope() -> IPCEnvelope? { nil }

    override func performDefaultImplementation() -> Any? {
        guard let envelope = makeEnvelope() else {
            if scriptErrorNumber == 0 { scriptErrorNumber = Int(errAEEventNotHandled) }
            return nil
        }
        let command = UncheckedCommand(command: self)
        // Apple events arrive on the main thread
        return MainActor.assumeIsolated { () -> Any? in
            guard let app = NSApp.delegate as? AppDelegate else {
                command.command.scriptErrorNumber = Int(errAEEventFailed)
                return nil
            }
            command.command.suspendExecution()
            Task { @MainActor in
                let reply = await app.automation.perform(envelope, source: .appleScript)
                if reply.isError {
                    command.command.scriptErrorNumber = Int(errAEEventFailed)
                    command.command.scriptErrorString = reply.stderr
                }
                command.command.resumeExecution(withResult: nil)
            }
            return nil
        }
    }

    private struct UncheckedCommand: @unchecked Sendable {
        let command: NSScriptCommand
    }
}

@objc(GreenshotCaptureCommand)
final class CaptureScriptCommand: GreenshotScriptCommand {
    /// The four-character codes of the dictionary's "capture mode" enumeration.
    private static let modes: [FourCharCode: AutomationCaptureMode] = [
        fourCharCode("GCrg"): .region, fourCharCode("GCwi"): .window, fourCharCode("GCfs"): .fullScreen,
        fourCharCode("GClr"): .lastRegion, fourCharCode("GCtx"): .text,
    ]

    override func makeEnvelope() -> IPCEnvelope? {
        var mode = AutomationCaptureMode.region
        if let code = directParameter as? NSNumber {
            guard let named = Self.modes[code.uint32Value] else {
                scriptErrorNumber = Int(errAEParamMissed)
                scriptErrorString = "Unknown capture mode."
                return nil
            }
            mode = named
        }
        var envelope = IPCEnvelope(command: IPCCommand.capture)
        envelope.setParameter("mode", mode.rawValue)
        return envelope
    }
}

@objc(GreenshotOpenClipboardCommand)
final class OpenClipboardScriptCommand: GreenshotScriptCommand {
    override func makeEnvelope() -> IPCEnvelope? { IPCEnvelope(command: IPCCommand.openClipboard) }
}

@objc(GreenshotShowSettingsCommand)
final class ShowSettingsScriptCommand: GreenshotScriptCommand {
    override func makeEnvelope() -> IPCEnvelope? {
        var envelope = IPCEnvelope(command: IPCCommand.settings)
        if let pane = evaluatedArguments?["pane"] as? String { envelope.setParameter("tab", pane) }
        return envelope
    }
}

@objc(GreenshotShowAboutCommand)
final class ShowAboutScriptCommand: GreenshotScriptCommand {
    override func makeEnvelope() -> IPCEnvelope? { IPCEnvelope(command: IPCCommand.about) }
}

@objc(GreenshotReloadSettingsCommand)
final class ReloadSettingsScriptCommand: GreenshotScriptCommand {
    override func makeEnvelope() -> IPCEnvelope? { IPCEnvelope(command: IPCCommand.reloadConfig) }
}

/// "GCrg" as the number Apple events use.
func fourCharCode(_ text: String) -> FourCharCode {
    text.utf8.prefix(4).reduce(FourCharCode(0)) { result, byte in (result << 8) | FourCharCode(byte) }
}
