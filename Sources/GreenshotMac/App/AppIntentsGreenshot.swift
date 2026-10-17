// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppIntents
import AppKit
import GreenshotCore

// Shortcuts, Siri and Spotlight actions (App Intents, Mac only). They run the same commands as greenshot-cli, with the
// source "shortcuts". scripts/build-app.sh extracts their metadata (appintentsmetadataprocessor) into
// Contents/Resources/Metadata.appintents, which is how Shortcuts finds them.

/// Why an action failed, as Shortcuts shows it.
struct AutomationIntentError: Error, CustomLocalizedStringResourceConvertible {
    var message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

@MainActor
enum AutomationIntents {
    static func run(_ envelope: IPCEnvelope) async throws {
        guard let app = NSApp.delegate as? AppDelegate else { throw AutomationIntentError(message: "Greenshot for Mac isn't ready.") }
        let reply = await app.automation.perform(envelope, source: .shortcuts)
        if reply.isError { throw AutomationIntentError(message: reply.stderr ?? "The action failed.") }
    }

    static func capture(_ mode: AutomationCaptureMode) async throws {
        var envelope = IPCEnvelope(command: IPCCommand.capture)
        envelope.setParameter("mode", mode.rawValue)
        try await run(envelope)
    }
}

enum CaptureModeIntentValue: String, AppEnum {
    case region, window, fullScreen, lastRegion, text

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Mode"
    static let caseDisplayRepresentations: [CaptureModeIntentValue: DisplayRepresentation] = [
        .region: "Region",
        .window: "Window",
        .fullScreen: "Full Screen",
        .lastRegion: "Last Region",
        .text: "Text (OCR)",
    ]

    var mode: AutomationCaptureMode {
        switch self {
        case .region: return .region
        case .window: return .window
        case .fullScreen: return .fullScreen
        case .lastRegion: return .lastRegion
        case .text: return .text
        }
    }
}

struct TakeScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Screenshot"
    static let description = IntentDescription("Takes a screenshot with Greenshot for Mac. It goes to your destinations, as with the hotkeys.")
    static let openAppWhenRun = false

    @Parameter(title: "Mode", default: .region)
    var mode: CaptureModeIntentValue

    static var parameterSummary: some ParameterSummary {
        Summary("Take a screenshot of \(\.$mode)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationIntents.capture(mode.mode)
        return .result()
    }
}

struct CaptureRegionIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Region"
    static let description = IntentDescription("Select a region of the screen to capture with Greenshot for Mac.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationIntents.capture(.region)
        return .result()
    }
}

struct CaptureWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Window"
    static let description = IntentDescription("Capture a window with Greenshot for Mac.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationIntents.capture(.window)
        return .result()
    }
}

struct CaptureFullScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Full Screen"
    static let description = IntentDescription("Capture the whole screen with Greenshot for Mac.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationIntents.capture(.fullScreen)
        return .result()
    }
}

struct OpenClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Clipboard in Greenshot"
    static let description = IntentDescription("Opens the image on the clipboard in the Greenshot for Mac editor.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationIntents.run(IPCEnvelope(command: IPCCommand.openClipboard))
        return .result()
    }
}

struct OpenImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Image in Greenshot"
    static let description = IntentDescription("Opens an image in the Greenshot for Mac editor.")
    static let openAppWhenRun = false

    @Parameter(title: "Image", supportedTypeIdentifiers: ["public.image"])
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        // A file the app can read is checked and opened like greenshot-cli's; otherwise its data opens as a screenshot
        if let url = image.fileURL, FileManager.default.isReadableFile(atPath: url.path) {
            var envelope = IPCEnvelope(command: IPCCommand.openFile)
            envelope.files = [url.path]
            try await AutomationIntents.run(envelope)
            return .result()
        }
        guard let loaded = ImageFileLoader.load(data: image.data), let app = NSApp.delegate as? AppDelegate else {
            throw AutomationIntentError(message: "The image could not be opened.")
        }
        let title = (image.filename as NSString).deletingPathExtension
        app.editors.open(Capture(image: loaded.image, scale: loaded.scale, title: title.isEmpty ? "Shortcuts" : title))
        return .result()
    }
}

struct GreenshotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CaptureRegionIntent(),
                    phrases: ["Capture a region with \(.applicationName)", "Take a screenshot with \(.applicationName)"],
                    shortTitle: "Capture Region", systemImageName: "rectangle.dashed")
        AppShortcut(intent: CaptureWindowIntent(), phrases: ["Capture a window with \(.applicationName)"],
                    shortTitle: "Capture Window", systemImageName: "macwindow")
        AppShortcut(intent: CaptureFullScreenIntent(), phrases: ["Capture the screen with \(.applicationName)"],
                    shortTitle: "Capture Full Screen", systemImageName: "display")
    }
}
