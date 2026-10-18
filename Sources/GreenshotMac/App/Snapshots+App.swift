// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

extension Snapshots {
    /// Renders for the menu bar menu, Settings and the app windows. Writes PNG files into `folder` with `write(_:to:)`; the helpers in Snapshots.swift
    /// (`editorWindow`, `overlay`, `form`, `settingsTab`, `capture`) do most of the work.
    static func renderAppExtras(to folder: URL, sample: CGImage, settings: SettingsStore) throws {
        // The whole General and Expert tabs (the standard renders stop at the window's height), and General in dark.
        let general = GeneralSettings(store: settings, status: SystemStatus())
        try write(fullForm(general, height: 1080), to: folder.appendingPathComponent("app-settings-general-full.png"))
        try write(fullForm(general, height: 1080, appearance: NSAppearance(named: .darkAqua)),
                  to: folder.appendingPathComponent("app-settings-general-dark.png"))
        try write(fullForm(ExpertSettings(store: settings), height: 760), to: folder.appendingPathComponent("app-settings-expert-full.png"))

        // The window picture beside the window list.
        let size = MenuBarThumbnailLayout.size(for: CGSize(width: sample.width, height: sample.height))
        let thumbnail = MenuBarWindowThumbnail.contentView(image: NSImage(cgImage: sample, size: size))
        try write(form(thumbnail), to: folder.appendingPathComponent("menubar-thumbnail.png"))

        // The About panel's text, as wide as the panel shows it.
        let credits = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 10))
        credits.textStorage?.setAttributedString(AppAboutCredits.make())
        credits.textContainerInset = NSSize(width: 8, height: 8)
        credits.isVerticallyResizable = true
        credits.sizeToFit()
        try write(form(credits), to: folder.appendingPathComponent("app-about-credits.png"))

        try renderDiagnostics(to: folder, settings: settings)
    }

    /// The log viewer, Self-Service, bug report, welcome and About windows, from fixed sample data (no live timers, no
    /// network, nothing of this Mac's state that changes between runs).
    private static func renderDiagnostics(to folder: URL, settings: SettingsStore) throws {
        let logFile = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-snapshot-\(UUID().uuidString).log")
        try Data(sampleLog.utf8).write(to: logFile)
        defer { try? FileManager.default.removeItem(at: logFile) }

        let viewer = LogViewerModel(fileURL: logFile, followsLog: false)
        viewer.load()
        try write(window(LogViewerView(model: viewer), size: NSSize(width: 900, height: 520)),
                  to: folder.appendingPathComponent("app-logviewer.png"))
        let search = LogViewerModel(fileURL: logFile, followsLog: false, search: "upload")
        search.load()
        search.wrap = true
        try write(window(LogViewerView(model: search), size: NSSize(width: 900, height: 420)),
                  to: folder.appendingPathComponent("app-logviewer-search.png"))

        let selfService = sampleSelfService(logFile: logFile)
        for section in SelfServiceSection.allCases {
            selfService.select(section)
            try write(window(SelfServiceView(model: selfService), size: NSSize(width: 900, height: section == .hotkeys ? 860 : 700)),
                      to: folder.appendingPathComponent("app-selfservice-\(section.rawValue).png"))
        }

        var welcomeFacts = SetupFacts(appName: AppInfo.name, currentVersion: "1.4.0")
        welcomeFacts.version = .checked(.upToDate(latest: "1.4.0"))
        welcomeFacts.canRecordScreen = false
        welcomeFacts.menuBarIconVisible = true
        welcomeFacts.hotkeyCount = 4
        let welcome = WelcomeModel(basics: WelcomeContent.basics(HotkeySettings()),
                                   setup: SetupModel(sample: welcomeFacts, loginOn: true),
                                   tips: WelcomeContent.tips(appName: AppInfo.name, showsCaptures: false), tipIndex: 2)
        // The first page with its language row (L10N-INFRA).
        welcome.languageStore = settings
        for step in WelcomeModel.Step.allCases {
            welcome.show(step)
            try write(window(WelcomeView(model: welcome), size: WelcomeView.windowSize(model: welcome)),
                      to: folder.appendingPathComponent("app-welcome-\(step.rawValue + 1)-\(step).png"))
        }
        let aboutHeight = AboutView.windowHeight()
        try write(window(AboutView(openSelfService: { _ in }, close: {}), size: NSSize(width: AboutView.textWidth + 48, height: aboutHeight)),
                  to: folder.appendingPathComponent("app-about.png"))

        let release = UpdateCheck.Release(version: "1.5.0", pageURL: UpdateCheck.releasesPageURL)
        let caught = BugReportModel(details: sampleException, environment: sampleEnvironment, settings: sampleSettings)
        caught.version = .known(.upToDate(latest: "1.4.0"))
        try write(window(BugReportView(model: caught, openSelfService: {}, close: {}), size: NSSize(width: 640, height: 640)),
                  to: folder.appendingPathComponent("app-bugreport.png"))
        let crash = BugReportModel(details: sampleCrash, environment: sampleEnvironment, settings: sampleSettings)
        crash.version = .known(.newer(release))
        crash.showsDetails = true
        try write(window(BugReportView(model: crash, openSelfService: {}, close: {}), size: NSSize(width: 640, height: 820)),
                  to: folder.appendingPathComponent("app-bugreport-crash.png"))
    }

    // MARK: Sample data

    static var sampleEnvironment: EnvironmentSnapshot {
        var snapshot = EnvironmentSnapshot(appName: AppInfo.name, version: "1.4.0", build: "140", architecture: "Apple silicon",
                                           osVersion: "Version 27.0 (Build 27A100)", now: Date(timeIntervalSince1970: 1_790_000_000))
        snapshot.model = "Mac15,3"
        snapshot.chip = "Apple M3"
        snapshot.physicalMemory = 16 << 30
        snapshot.appMemory = 84 << 20
        snapshot.peakMemory = 131 << 20
        snapshot.threads = 9
        snapshot.launched = Date(timeIntervalSince1970: 1_790_000_000 - 8_130)
        snapshot.locale = "en_GB"
        snapshot.thermalState = "nominal"
        snapshot.screens = [
            .init(name: "Built-in Retina Display", width: 1512, height: 982, scale: 2, refreshRate: 120, edrNow: 1, edrPotential: 16,
                  colorSpace: "Color LCD", isMain: true),
            .init(name: "DELL U2720Q", width: 2560, height: 1440, scale: 1, refreshRate: 60, colorSpace: "sRGB IEC61966-2.1"),
        ]
        return snapshot
    }

    static var sampleSettings: AppSettings {
        var settings = AppSettings()
        settings.outputFormat = .jpg
        settings.jira.url = "https://example.atlassian.net"
        return settings
    }

    static let sampleException = CrashDetails(
        kind: .caughtException, type: "NSRangeException",
        message: "*** -[__NSArrayM objectAtIndex:]: index 3 beyond bounds [0 .. 2]",
        frames: [CrashFrame(image: "CoreFoundation", symbol: "__exceptionPreprocess"),
                 CrashFrame(image: "libobjc.A.dylib", symbol: "objc_exception_throw"),
                 CrashFrame(image: "CoreFoundation", symbol: "-[__NSArrayM objectAtIndex:]"),
                 CrashFrame(image: "GreenshotMac", symbol: "EditorWindowController.undo(_:)"),
                 CrashFrame(image: "AppKit", symbol: "-[NSApplication(NSResponder) sendAction:to:from:]")])

    static let sampleCrash = CrashDetails(
        kind: .crashReport, type: "EXC_BREAKPOINT (SIGTRAP)",
        message: "GreenshotMac/CaptureCoordinator.swift:120: Fatal error: Unexpectedly found nil while unwrapping an Optional value",
        frames: [CrashFrame(image: "libswiftCore.dylib", symbol: "Swift._assertionFailure(_:_:file:line:flags:)"),
                 CrashFrame(image: "GreenshotMac", symbol: "CaptureCoordinator.finish(_:)"),
                 CrashFrame(image: "GreenshotMac", symbol: "closure #1 in CaptureCoordinator.captureRegion()"),
                 CrashFrame(image: "AppKit", symbol: "-[NSApplication run]")],
        reportFile: "GreenshotMac-2026-10-17-124218.ips")

    private static func sampleSelfService(logFile: URL) -> SelfServiceModel {
        var facts = SetupFacts(appName: AppInfo.name, currentVersion: "1.4.0")
        facts.version = .checked(.upToDate(latest: "1.4.0"))
        facts.canRecordScreen = false
        facts.menuBarIconVisible = true
        facts.hotkeyCount = 4
        facts.refusedHotkeys = ["Capture window (⌃⌥⌘5)"]
        facts.loginItem = .on
        let setup = SetupModel(sample: facts, loginOn: true)

        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsFile = FilesSectionModel.FileInfo(url: home.appendingPathComponent("Library/Preferences/io.github.greenshot-mac.GreenshotMac.plist"),
                                                      exists: true, size: "6.2 KB", modified: "2026-10-17 09:12:01")
        let log = FilesSectionModel.FileInfo(url: AppInfo.logFile, exists: true, size: "182.4 KB", modified: "2026-10-17 09:21:05")
        let files = FilesSectionModel(settingsFile: settingsFile, logFile: log,
                                      glance: FilesSectionModel.glance(of: FilesSectionModel.info(logFile)), crashReports: 1)

        let clipboard = ClipboardSectionModel(sample: ["public.png", "public.tiff", "public.html", "org.nspasteboard.AutoGeneratedType"],
                                              changeCount: 1_204, source: "Greenshot for Mac (Community) (io.github.greenshot-mac.GreenshotMac)",
                                              monitorLog: ["09:30:01  Started watching the clipboard (every 600 ms)",
                                                           "09:30:07  Changed (#1203): public.utf8-plain-text",
                                                           "09:30:12  Changed (#1204): public.png, public.tiff, public.html"])

        let system = SystemScreenshotShortcut.defaults.map { shortcut -> SystemScreenshotShortcut in
            var copy = shortcut
            if shortcut.id == 29 { copy.enabled = false }
            return copy
        }
        var hotkeySettings = HotkeySettings()
        hotkeySettings.text = KeyCombo(keyCode: 21, modifiers: KeyCombo.shift | KeyCombo.command)
        let rows = HotkeyStatus.rows(hotkeySettings, registered: HotkeyStatus.slots(hotkeySettings).compactMap(\.combo),
                                     refused: [KeyCombo.defaultWindow], systemShortcuts: system)
        let contenders = CaptureAppContender.known.map {
            HotkeysSectionModel.Contender(name: $0.name, note: $0.note, running: $0.name == "Dropbox")
        }
        let hotkeys = HotkeysSectionModel(rows: rows, systemShortcuts: system, conflictIDs: [30], contenders: contenders)

        let integrity = IntegritySectionModel(sample: SignatureReport(
            location: "/Applications/Greenshot for Mac (Community).app", isAppBundle: true, valid: true,
            validity: "Valid: no file of the app was changed", signer: "Greenshot Dev", identifier: "io.github.greenshot-mac.GreenshotMac",
            teamID: nil, hardenedRuntime: true, cdHash: "3f2a9c41d07be6a1c95d0e4b8a7f61c2d3e4f5a6", notarization: .notApplicable,
            quarantined: false, translocated: false))
        let model = SelfServiceModel(section: .system, system: SystemSectionModel(sample: sampleEnvironment), setup: setup,
                                     files: files, clipboard: clipboard, hotkeys: hotkeys, integrity: integrity)
        model.status = "Updated at 09:30:12"
        return model
    }

    /// A SwiftUI view in a window of `size`, rendered.
    static func window(_ view: some View, size: NSSize, appearance: NSAppearance? = NSAppearance(named: .aqua)) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.appearance = appearance
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        keepAlive.append(window)
        hosting.layoutSubtreeIfNeeded()
        // Lets AppKit views inside (text views, tables) lay out and scroll before the picture is taken.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }

    /// A log as the app writes it, with an error, a multi-line entry and an upload.
    static let sampleLog = """
        2026-10-17 09:12:01,114 [main] INFO  - [App] Starting: Greenshot for Mac (Community) 1.4.0 (build 140, Apple silicon), macOS Version 27.0 (Build 27A100)
        2026-10-17 09:12:01,162 [main] INFO  - [Hotkeys] Registered 4 hotkeys
        2026-10-17 09:12:21,508 [9731] INFO  - [Update] Update check: newest release 1.4.0, this is 1.4.0
        2026-10-17 09:15:42,019 [main] INFO  - [Capture] Captured region 1280x720 on Built-in Retina Display
        2026-10-17 09:15:44,377 [main] INFO  - [Output] Saved ~/Desktop/2026-10-17 09_15_42-Safari.png
        2026-10-17 09:16:03,880 [main] DEBUG - [Editor] Opened an editor for 2026-10-17 09_15_42-Safari.png
        2026-10-17 09:17:10,245 [8812] WARN  - [Upload] Upload to Jira failed, trying again
            Foundation.URLError: The request timed out. (NSURLErrorDomain -1001)
        2026-10-17 09:17:16,902 [8812] INFO  - [Upload] Upload to Jira finished: SHOT-12
        2026-10-17 09:20:31,450 [main] ERROR - [Alert] The screenshot could not be taken
            Swift.CocoaError: You don’t have permission to save the file. (NSCocoaErrorDomain 513)
        2026-10-17 09:21:05,013 [main] INFO  - [Capture] Captured window "Quarterly report – Numbers" 1440x900

        """

    /// A settings form at full length, in the light or the given appearance.
    private static func fullForm(_ view: some View, height: CGFloat, appearance: NSAppearance? = NSAppearance(named: .aqua)) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view.frame(width: 620, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: height)
        hosting.appearance = appearance
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }
}
