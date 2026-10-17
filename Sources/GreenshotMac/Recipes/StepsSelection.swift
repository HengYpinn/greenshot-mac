// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// Upstream `InteractiveSelectionStep` (Greenshot/Recipes/Steps/InteractiveSelectionStep.cs) on the Mac's capture
/// screen: the frozen displays of the Source before it, the selection mode of the step, the window snapping; the
/// selection crops the capture and is remembered (last region, recent and fixed sizes) like `CaptureCoordinator` does.
/// A capture handed to the flow, or one not taken from the screen, is used as a whole (Text: its OCR text).
struct RecipeInteractiveSelectionExecutor: RecipeStepExecutor {
    let runtime: RecipeRuntime

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard var payload = context.payload else {
            context.abort("No raw capture available for interactive selection.")
            return
        }
        if RecipeSourceValues.region(context[variable: "PreSuppliedRegion"]) != nil {
            context.log("Interactive selection skipped: the region was given.")
            return
        }
        let modeName = step.string("SelectionMode")?.trimmingCharacters(in: .whitespaces) ?? "Region"
        guard !context.isPayloadPreSupplied, let screens = payload.attachments[RecipeFrozenScreens.key] as? RecipeFrozenScreens else {
            if recipeEquals(modeName, "Text") {
                let language = context.environment.configValue("ocrLanguage")?.asString ?? ""
                let text = try await RecipeVision.text(of: payload.flattened() ?? payload.image, language: language)
                payload.extractedText = text
                context.payload = payload
            }
            return
        }
        context.state = .selecting
        var mode = Self.mode(modeName)
        if let tool = step.string("SelectionTool")?.trimmingCharacters(in: .whitespaces), !tool.isEmpty {
            if recipeEquals(tool, "FixedSize") {
                mode = .fixedSize
            } else {
                log.info("Capture tool '\(tool)' isn't there on the Mac; the capture screen starts in the selection mode.")
            }
        }
        let snapping = step.bool("AllowWindowSnapping") ?? true
        let outcome = await Self.select(screens, mode: mode, snapping: snapping, runtime: runtime)
        // The capture screen is closed: another one may open (RecipeRuntime.launch).
        await MainActor.run { runtime.releaseSelection(of: context.executionId) }
        payload.attachments[RecipeFrozenScreens.key] = nil
        switch outcome {
        case .cancelled:
            context.abort("User cancelled interactive selection.")
            return
        case .barcodeAction:
            context.abort("A QR code's action was used on the capture screen.")
            return
        case .selected(let selected, let window):
            if let window {
                context[variable: "SelectedWindow"] = RecipeSourceValues.windowValue(id: window.id, title: window.displayTitle,
                                                                                     app: window.appName, pid: window.pid, frame: window.frame)
                context.setObject(RecipeWindowObject(window: window), forKey: "SelectedWindow")
            }
            var cropped = selected
            cropped.sourceType = payload.sourceType
            cropped.metadata = payload.metadata
            cropped.metadata["WindowTitle"] = .string(selected.title)
            if let text = selected.extractedText { cropped.metadata["CaptureMode"] = .string("Text"); cropped.extractedText = text }
            // An AI tool gets the selection with the excluded apps' windows blacked out, like a Source's picture (SM-L2).
            if recipeEquals(context.trigger?.triggerType ?? "", WellKnownTriggerType.aiTool),
               let guardian = await MainActor.run(body: { runtime.aiToolCaptureGuard }) {
                cropped = RecipeSourceExecutor.redacted(cropped, guard: guardian, context: context)
            }
            context.payload = cropped
        }
    }

    static func mode(_ name: String) -> CaptureOverlayController.Mode {
        switch name.lowercased() {
        case "window": return .window
        case "text": return .text
        default: return .region
        }
    }

    enum Outcome {
        case cancelled
        case barcodeAction
        case selected(RecipePayload, window: WindowInfo?)
    }

    /// The capture screen on the frozen displays; the selection as a payload (`CaptureCoordinator.interactive`).
    @MainActor
    private static func select(_ screens: RecipeFrozenScreens, mode: CaptureOverlayController.Mode, snapping: Bool,
                               runtime: RecipeRuntime) async -> Outcome {
        let settings = runtime.app.settings
        let frozen = screens.frozen
        guard let selection = await CaptureOverlayController.select(screens: frozen.plain, pointerScreens: frozen.pointer,
                                                                    windows: snapping ? screens.windows : [], mode: mode,
                                                                    settings: settings)
        else { return .cancelled }
        if let action = selection.barcodeAction {
            switch action {
            case .copy(let text): Clipboard.copy(text: text)
            case .open(let url): NSWorkspace.shared.open(url)
            }
            return .barcodeAction
        }
        let title = selection.window?.displayTitle ?? ScreenCapturer.title(for: selection.rect, in: screens.windows)
        // Text: the picture of the selected words, its text; the last region and the sizes stay.
        if let text = selection.text {
            guard let result = ScreenComposer.image(of: selection.rect, from: frozen.screens(withPointer: selection.includesPointer))
            else { return .cancelled }
            var payload = RecipePayload(image: result.image, scale: result.scale, title: title)
            payload.extractedText = text
            payload.attachments[RecipeSourceExecutor.originKey] = RecipeScreenOrigin(origin: selection.rect.origin)
            return .selected(payload, window: selection.window)
        }
        guard let capture = frozen.capture(of: selection.rect, withPointer: selection.includesPointer, title: title) else {
            return .cancelled
        }
        let size = CaptureSize(width: capture.image.width, height: capture.image.height)
        settings.update { values in
            values.lastCapturedRegion = selection.rect
            if selection.mode == .region || selection.mode == .fixedSize {
                values.recentCaptureSizes = FixedSizeCapture.remember(size, in: values.recentCaptureSizes)
            }
            if let fixed = selection.fixedSize { values.fixedCaptureSize = fixed }
        }
        var payload = RecipePayload(capture: capture, sourceType: "Region")
        payload.attachments[RecipeSourceExecutor.originKey] = RecipeScreenOrigin(origin: selection.rect.origin)
        return .selected(payload, window: selection.window)
    }
}

/// Vision's text recognition for the steps, through Core's async recognition, which runs Vision off the cooperative
/// pool (its synchronous perform blocks its thread while it waits for work that may need a pool thread).
enum RecipeVision {
    static func text(of image: CGImage, language: String = "") async throws -> String {
        let lines = try await TextRecognizer.recognizeLines(in: image, language: language)
        return lines.map(\.text).joined(separator: "\n")
    }
}
