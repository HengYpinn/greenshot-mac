// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// Upstream `SourceAcquisitionStep` (Greenshot/Recipes/Steps/SourceAcquisitionStep.cs) with its capture sources: the
/// screen for a selection after it (Region, Window, TextOcr), the active or a matching window, full screen, the last
/// region, the clipboard, a file, the open editor; a capture handed to the flow is kept. The screen parts are the ones
/// `CaptureCoordinator` uses (permission, delay, frozen displays, HDR, window shadow, the pointer as an element).
struct RecipeSourceExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        if context.payload != nil {
            // Forwarded, from the browser extension or a notification: the capture is used as it is.
            context.isPayloadPreSupplied = true
            context.log("Source \(step.node.displayName) uses the capture handed to the flow.")
            return
        }
        guard let type = RecipeSourceValues.sourceType(step) else {
            throw RecipeStepError("Unsupported capture source type: \(step.string("SourceType") ?? "")", errorType: "NotSupportedException")
        }
        context.state = .acquiring
        let isAITool = recipeEquals(context.trigger?.triggerType ?? "", WellKnownTriggerType.aiTool)
        let services = await MainActor.run { RecipeSourceServices(runtime: runtime) }
        let settings = services.settings
        let captureMouse = RecipeSourceValues.bool(step, "CaptureMouseCursor", variable: "CaptureMouseCursor", in: context,
                                                   setting: settings.captureMousePointer)
        let region = RecipeSourceValues.region(context[variable: "PreSuppliedRegion"])
        let fromScreen = region != nil || type.isScreen
        if fromScreen {
            let allowed = await MainActor.run { () -> Bool in
                guard Permissions.ensureScreenCapture() else { return false }
                Toast.dismiss()
                if !isAITool {
                    let state = runtime.flowState(context.executionId)
                    state.capturedFromScreen = true
                    state.previousApp = context.trigger?.frontmostProcessID
                }
                return true
            }
            guard allowed else {
                context.abort("Greenshot may not record the screen.")
                return
            }
        }
        let delay = RecipeSourceValues.clampedDelay(RecipeSourceValues.int(step, "DelayMs", variable: "CaptureDelay", in: context,
                                                                           setting: settings.captureDelayMilliseconds))
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000) }
        try Task.checkCancellation()

        var payload: RecipePayload
        if let region {
            payload = try await captureRegion(region, withPointer: captureMouse, settings: settings)
        } else {
            switch type {
            case .region, .textOcr:
                payload = try await freezeScreens(withPointer: captureMouse, settings: settings)
            case .window:
                payload = try await windowSource(step, context: context, services: services, captureMouse: captureMouse,
                                                 interactive: true)
            case .activeWindow:
                payload = try await windowSource(step, context: context, services: services, captureMouse: captureMouse,
                                                 interactive: false)
            case .fullScreen:
                payload = try await fullScreen(step, context: context, withPointer: captureMouse, settings: settings)
            case .lastRegion:
                guard let last = settings.lastCapturedRegion, !last.isEmpty else {
                    // Upstream `LastRegionCaptureSource` aborts; the Mac beeps like its own Capture Last Region.
                    await MainActor.run { NSSound.beep() }
                    context.abort("There is no last region to capture.")
                    return
                }
                payload = try await captureRegion(last, withPointer: captureMouse, settings: settings)
                if let window = await MainActor.run(body: { Self.window(under: last) }) {
                    context[variable: "SelectedWindow"] = RecipeSourceValues.windowValue(id: window.id, title: window.displayTitle,
                                                                                         app: window.appName, pid: window.pid,
                                                                                         frame: window.frame)
                    context.setObject(RecipeWindowObject(window: window), forKey: "SelectedWindow")
                }
            case .clipboard:
                payload = try await clipboard()
            case .file:
                payload = try await file(step, context: context)
            case .currentEditor:
                payload = try await currentEditor(context)
            case .extension:
                throw RecipeStepError("Extension capture source requires a pre-supplied image payload.", errorType: "InvalidOperationException")
            }
        }
        if payload.sourceType == nil { payload.sourceType = type.rawValue }
        payload.metadata["CaptureMode"] = .string(type.rawValue)
        if !payload.title.isEmpty { payload.metadata["WindowTitle"] = .string(payload.title) }
        if isAITool, payload.metadata["source"]?.asString == "Screen", let guardian = services.aiGuard {
            payload = Self.redacted(payload, guard: guardian, context: context)
        }
        context.payload = payload
        context.log("Acquired \(type.rawValue): \(payload.image.width) × \(payload.image.height) px")
    }

    // MARK: Screen

    /// Region, Window (to select), TextOcr: every display frozen with and without the pointer for the selection after
    /// it; the payload is the union of the displays until then (upstream captures the full screen first).
    @MainActor
    private func freezeScreens(withPointer: Bool, settings: AppSettings) async throws -> RecipePayload {
        let windows = ScreenCapturer.onScreenWindows(includingPanels: true)
        let frozen = try await ScreenCapturer.freeze(withPointer: true, toneMapHDR: settings.toneMapHDRCaptures)
        let bounds = ScreenComposer.union(of: frozen.plain)
        guard let picture = ScreenComposer.image(of: bounds, from: frozen.screens(withPointer: withPointer)) else {
            throw CaptureError.nothingToCapture
        }
        var payload = RecipePayload(image: picture.image, scale: picture.scale, title: ScreenCapturer.title(for: bounds, in: windows))
        payload.metadata["source"] = .string("Screen")
        payload.attachments[RecipeFrozenScreens.key] = RecipeFrozenScreens(frozen: frozen, windows: windows, withPointer: withPointer,
                                                                           bounds: bounds)
        return payload
    }

    /// A part of the screen (PreSuppliedRegion, LastRegion).
    @MainActor
    private func captureRegion(_ rect: CGRect, withPointer: Bool, settings: AppSettings) async throws -> RecipePayload {
        let windows = ScreenCapturer.onScreenWindows()
        let frozen = try await ScreenCapturer.freeze(withPointer: withPointer, toneMapHDR: settings.toneMapHDRCaptures)
        guard let capture = frozen.capture(of: rect, withPointer: withPointer, title: ScreenCapturer.title(for: rect, in: windows)) else {
            throw CaptureError.nothingToCapture
        }
        var payload = RecipePayload(capture: capture, sourceType: "Region")
        payload.metadata["source"] = .string("Screen")
        payload.attachments[Self.originKey] = RecipeScreenOrigin(origin: rect.origin)
        return payload
    }

    /// Upstream `ScreenCaptureSource` with `ScreenCaptureMode`: the display with the mouse (Auto), every display, display
    /// number `screenToCapture` (Fixed), or the menu bar's display (`TargetDisplay`).
    @MainActor
    private func fullScreen(_ step: RecipeStepInvocation, context: RecipeFlowContext, withPointer: Bool,
                            settings: AppSettings) async throws -> RecipePayload {
        let mode = RecipeSourceValues.screenCaptureMode(step, in: context, setting: settings.screenCaptureMode)
        let target = (context.object(forKey: "TargetDisplay") as? RecipeDisplayObject)?.displayID
        let windows = ScreenCapturer.onScreenWindows()
        let frozen = try await ScreenCapturer.freeze(withPointer: withPointer, toneMapHDR: settings.toneMapHDRCaptures)
        let order = NSScreen.screens.map(\.displayID)
        let ordered = frozen.screens(withPointer: withPointer).sorted {
            (order.firstIndex(of: $0.displayID) ?? Int.max) < (order.firstIndex(of: $1.displayID) ?? Int.max)
        }
        let chosen: [FrozenScreen]
        if let target {
            chosen = ordered.filter { $0.displayID == target }
        } else {
            let mouse = context.trigger?.cursorLocation ?? ScreenSpace.mouseLocation
            chosen = CaptureScreenChoice.screens(for: mode, screenNumber: settings.screenToCapture, mouse: mouse,
                                                 frames: ordered.map(\.frame)).map { ordered[$0] }
        }
        let title = ScreenCapturer.frontWindow(in: windows)?.displayTitle ?? "Full screen"
        let union = ScreenComposer.union(of: chosen)
        guard !chosen.isEmpty,
              let capture = frozen.capture(of: union, withPointer: withPointer, title: title, only: Set(chosen.map(\.displayID)))
        else { throw CaptureError.nothingToCapture }
        var payload = RecipePayload(capture: capture, sourceType: "FullScreen")
        payload.metadata["source"] = .string("Screen")
        payload.attachments[Self.originKey] = RecipeScreenOrigin(origin: union.origin)
        return payload
    }

    // MARK: Windows

    /// Window and ActiveWindow (upstream `ActiveWindowCaptureSource` and the `WindowHandle` path): a given window
    /// (`WindowHandle`, `TargetWindow`), a matching one (`WindowTitle`, `WindowTitlePattern`, `ProcessName`), else the
    /// window that was active when the flow was started. A Window source without any of these is the screen for the
    /// selection.
    private func windowSource(_ step: RecipeStepInvocation, context: RecipeFlowContext, services: RecipeSourceServices,
                              captureMouse: Bool, interactive: Bool) async throws -> RecipePayload {
        let handle = interactive ? RecipeSourceValues.windowReference(step.isSet("WindowHandle") ? step.parameters["WindowHandle"] : nil) : .none
        var windowID: CGWindowID?
        switch handle {
        case .none:
            break
        case .id(let id):
            windowID = id
        case .other(let reference):
            guard let id = services.windowResolver?.windowID(for: reference) else {
                throw RecipeStepError("The window to capture (\(reference.interpolationText)) doesn't exist (anymore).",
                                      errorType: "InvalidOperationException")
            }
            windowID = id
        }
        let query = Self.windowQuery(step, context: context)
        if windowID == nil, query.isEmpty, interactive, context.object(forKey: "TargetWindow") == nil {
            return try await freezeScreens(withPointer: captureMouse, settings: services.settings)
        }
        let isAITool = recipeEquals(context.trigger?.triggerType ?? "", WellKnownTriggerType.aiTool)
        let target = (context.object(forKey: "TargetWindow") as? RecipeWindowObject)?.window
        let frontPID = context.trigger?.frontmostProcessID
        let wantedID = windowID
        let window: WindowInfo? = await MainActor.run {
            let windows = ScreenCapturer.onScreenWindows(includingPanels: true)
            if let wantedID { return windows.first { $0.id == wantedID } }
            if let target { return windows.first { $0.id == target.id } ?? target }
            if !query.isEmpty {
                let active = windows.first { $0.pid == frontPID && $0.level == 0 }
                if let found = query.firstMatch(in: windows.filter { $0.level == 0 }, active: active, title: \.title,
                                                names: { [$0.appName] }) {
                    return found
                }
                log.warn("No window matches the recipe's window (title, pattern or process); using the active one.")
            }
            let normal = windows.filter { $0.level == 0 }
            return normal.first { $0.pid == frontPID } ?? ScreenCapturer.frontWindow(in: normal)
        }
        guard let window else {
            if let windowID {
                throw RecipeStepError("The window to capture (\(windowID)) doesn't exist (anymore).", errorType: "InvalidOperationException")
            }
            throw CaptureError.windowNotFound
        }
        if isAITool, let refusal = services.aiGuard?.refusal(for: window) {
            throw RecipeStepError(refusal, errorType: "UnauthorizedAccessException")
        }
        let capture = try await Self.capture(window, showsCursor: captureMouse, settings: services.settings)
        var payload = RecipePayload(capture: capture, sourceType: interactive ? "Window" : "ActiveWindow")
        // Upstream `ActiveWindowCaptureSource` and AI tool captures: "Window" (the window's own content).
        payload.metadata["source"] = .string("Window")
        payload.metadata["ProcessName"] = .string(window.appName)
        return payload
    }

    @MainActor
    private static func capture(_ window: WindowInfo, showsCursor: Bool, settings: AppSettings) async throws -> Capture {
        try await ScreenCapturer.capture(window: window, showsCursor: showsCursor, includeShadow: settings.includeWindowShadow,
                                         toneMapHDR: settings.toneMapHDRCaptures)
    }

    /// The window parameters, else the same variables (upstream reads both).
    private static func windowQuery(_ step: RecipeStepInvocation, context: RecipeFlowContext) -> WindowMatchQuery {
        func text(_ name: String) -> String? {
            RecipeSourceValues.string(step, name, variable: nil, in: context)
                ?? context[variable: name]?.asString.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        let matchCase = step.isSet("MatchCase") ? step.bool("MatchCase") : context[variable: "MatchCase"]?.asBool
        return WindowMatchQuery(title: text("WindowTitle"), titlePattern: text("WindowTitlePattern"), processName: text("ProcessName"),
                                matchCase: matchCase ?? false)
    }

    /// The normal window under the middle of `rect` (LastRegion's `SelectedWindow`).
    @MainActor
    static func window(under rect: CGRect) -> WindowInfo? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return ScreenCapturer.onScreenWindows().first { $0.level == 0 && $0.frame.contains(center) }
    }

    // MARK: Clipboard, file, editor

    /// Upstream `ClipboardCaptureSource`: the image on the clipboard, or the image a copied web page part shows.
    @MainActor
    private func clipboard() async throws -> RecipePayload {
        let pasted: (image: CGImage, scale: CGFloat)?
        if let image = Clipboard.image() {
            pasted = image
        } else {
            pasted = await ImageLoader.downloadedHTMLImage()
        }
        guard let pasted else {
            throw RecipeStepError("There is no image on the clipboard.", errorType: "InvalidOperationException")
        }
        var payload = RecipePayload(image: pasted.image, scale: pasted.scale, title: "Clipboard")
        payload.metadata["source"] = .string("Clipboard")
        return payload
    }

    /// Upstream `FileCaptureSource`: `Filename`, else the variable Filename; a `.greenshot` file with its elements.
    private func file(_ step: RecipeStepInvocation, context: RecipeFlowContext) async throws -> RecipePayload {
        guard let name = RecipeSourceValues.string(step, "Filename", variable: nil, in: context)
                ?? context[variable: "Filename"]?.asString?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            throw RecipeStepError("No file to load: set Filename or the variable Filename.", errorType: "ArgumentException")
        }
        let url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RecipeStepError("The file \(url.lastPathComponent) doesn't exist.", errorType: "FileNotFoundException")
        }
        let title = url.deletingPathExtension().lastPathComponent
        var payload: RecipePayload
        if GreenshotFile.isGreenshotFile(url) {
            guard let contents = GreenshotFile.read(contentsOf: url) else {
                throw RecipeStepError("The Greenshot file \(url.lastPathComponent) could not be read.", errorType: "InvalidDataException")
            }
            payload = RecipePayload(image: contents.image, scale: contents.scale, title: contents.title ?? title,
                                    captureDate: contents.captureDate ?? Date())
            payload.annotations = contents.elements
        } else {
            guard let loaded = ImageLoader.load(url) else {
                throw RecipeStepError("The image \(url.lastPathComponent) could not be opened.", errorType: "InvalidDataException")
            }
            payload = RecipePayload(image: loaded.image, scale: loaded.scale, title: title)
        }
        payload.fileURL = url
        payload.metadata["source"] = .string("File")
        return payload
    }

    /// Upstream `CurrentEditorCaptureSource`: the editor of the Editor trigger ("EditorForm").
    private func currentEditor(_ context: RecipeFlowContext) async throws -> RecipePayload {
        let form = context.object(forKey: "EditorForm") as? RecipeEditorForm
        let payload: RecipePayload? = await MainActor.run {
            guard let editor = form?.editor else { return nil }
            editor.canvas.commitEditing()
            return RecipePayload(document: editor.editorDocument)
        }
        guard let payload else {
            throw RecipeStepError("There is no editor to take the image from.", errorType: "InvalidOperationException")
        }
        return payload
    }

    // MARK: AI tools

    static let originKey = "RecipeScreenOrigin"

    /// The windows of apps excluded from AI tools blacked out of a screen capture (upstream `RedactForAiTool`), off the
    /// main thread.
    private static func redacted(_ payload: RecipePayload, guard guardian: any RecipeAIToolCaptureGuard,
                                 context: RecipeFlowContext) -> RecipePayload {
        var changed = payload
        let origin = (payload.attachments[originKey] as? RecipeScreenOrigin)?.origin
            ?? (payload.attachments[RecipeFrozenScreens.key] as? RecipeFrozenScreens)?.bounds.origin ?? .zero
        // The pointer element would be drawn over the blacked-out area: an AI tool's capture has no pointer anyway.
        let flat = payload.flattened() ?? payload.image
        let result = guardian.redacted(flat, scale: payload.scale, origin: origin)
        if result.count > 0 {
            changed.image = result.image
            changed.annotations = []
            context.log("Blacked out \(result.count) window(s) of applications excluded from AI tools.")
        }
        return changed
    }
}

/// Where a screen payload's top left is (Quartz global points), for the AI tools' redaction.
struct RecipeScreenOrigin: Sendable {
    let origin: CGPoint
}

/// What the Source reads on the main actor once.
struct RecipeSourceServices: @unchecked Sendable {
    let settings: AppSettings
    let windowResolver: (any RecipeWindowResolving)?
    let aiGuard: (any RecipeAIToolCaptureGuard)?

    @MainActor
    init(runtime: RecipeRuntime) {
        settings = runtime.app.settings.value
        windowResolver = runtime.windowResolver
        aiGuard = runtime.aiToolCaptureGuard
    }
}

/// Upstream `ImmediateFeedbackStep`: the camera sound after a capture, not for a capture handed to the flow, nor for an
/// AI tool's capture.
struct RecipeImmediateFeedbackExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard !context.isPayloadPreSupplied else { return }
        guard !recipeEquals(context.trigger?.triggerType ?? "", WellKnownTriggerType.aiTool) else { return }
        let settings = await MainActor.run { runtime.app.settings.value }
        let play = RecipeSourceValues.bool(step, "PlaySound", variable: "PlayShutterSound", in: context, setting: settings.playCameraSound)
        guard play else { return }
        let file = RecipeSourceValues.string(step, "SoundFilePath", variable: "SoundFilePath", in: context) ?? settings.notificationSound
        await MainActor.run { CameraSound.play(file: file) }
    }
}
