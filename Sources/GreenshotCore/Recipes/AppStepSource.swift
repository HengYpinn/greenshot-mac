// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The values of the app's capture steps (Source, InteractiveSelection, ImmediateFeedback, RecordVideo) that need no
/// screen: parsing and the three-tier precedence of docs/capture-recipes.md §5 (run-time variable, node parameter,
/// setting). Ports of the `Resolve*` helpers of upstream `SourceAcquisitionStep.cs` and `ImmediateFeedbackStep.cs`.
public enum RecipeSourceValues {
    /// The capture types of the Source step (upstream `CaptureSourceType`).
    public enum SourceType: String, CaseIterable, Sendable {
        case region = "Region"
        case window = "Window"
        case activeWindow = "ActiveWindow"
        case fullScreen = "FullScreen"
        case lastRegion = "LastRegion"
        case clipboard = "Clipboard"
        case file = "File"
        case textOcr = "TextOcr"
        case currentEditor = "CurrentEditor"
        case `extension` = "Extension"

        /// Upstream's `Enum.Parse` also takes the numbers of the enum.
        public init?(name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if let number = Int(trimmed), Self.allCases.indices.contains(number) {
                self = Self.allCases[number]
                return
            }
            guard let match = Self.allCases.first(where: { recipeEquals($0.rawValue, trimmed) }) else { return nil }
            self = match
        }

        /// Taken from the screen: the selection works on it, AI tools get excluded windows blacked out.
        public var isScreen: Bool {
            switch self {
            case .region, .window, .activeWindow, .fullScreen, .lastRegion, .textOcr: return true
            case .clipboard, .file, .currentEditor, .extension: return false
            }
        }
    }

    /// The Source's type: from the parameter only (never a variable: a caller must not turn a screen capture into a file
    /// read), default Region. Nil for a value that is no type.
    public static func sourceType(_ step: RecipeStepInvocation) -> SourceType? {
        guard let text = step.string("SourceType"), !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .region }
        return SourceType(name: text)
    }

    /// The run-time variable, the node parameter, else `setting` (upstream `ResolveCaptureMouse` and friends).
    public static func bool(_ step: RecipeStepInvocation, _ name: String, variable: String?, in context: RecipeFlowContext,
                            setting: Bool) -> Bool {
        step.resolved(name, overrideVariable: variable, in: context)?.asBool ?? setting
    }

    public static func int(_ step: RecipeStepInvocation, _ name: String, variable: String?, in context: RecipeFlowContext,
                           setting: Int) -> Int {
        step.resolved(name, overrideVariable: variable, in: context)?.asInt ?? setting
    }

    /// A text value; empty counts as not set.
    public static func string(_ step: RecipeStepInvocation, _ name: String, variable: String?, in context: RecipeFlowContext) -> String? {
        guard let text = step.resolved(name, overrideVariable: variable, in: context)?.asString?.trimmingCharacters(in: .whitespaces),
              !text.isEmpty else { return nil }
        return text
    }

    /// `ScreenCaptureMode` of the variable, the parameter, else the setting (Auto, FullScreen, Fixed; numbers 0-2).
    public static func screenCaptureMode(_ step: RecipeStepInvocation, in context: RecipeFlowContext,
                                         setting: ScreenCaptureMode) -> ScreenCaptureMode {
        for value in [context[variable: "ScreenCaptureMode"], step.isSet("ScreenCaptureMode") ? step.parameters["ScreenCaptureMode"] : nil] {
            if let mode = value.flatMap(screenCaptureMode(_:)) { return mode }
        }
        return setting
    }

    public static func screenCaptureMode(_ value: JSONValue) -> ScreenCaptureMode? {
        guard let text = value.asString?.trimmingCharacters(in: .whitespaces) else { return nil }
        switch text.lowercased() {
        case "auto", "0": return .auto
        case "fullscreen", "1": return .fullScreen
        case "fixed", "2": return .fixed
        default: return nil
        }
    }

    /// A region in Quartz global points (top-left origin, like `list_windows`): "x,y,width,height" (what a Region argument
    /// binds), an object `{x, y, width, height}` (also left/top), or a host `CGRect`. Nil when it isn't one or is empty.
    public static func region(_ value: JSONValue?) -> CGRect? {
        guard let value, !value.isNull else { return nil }
        var rect: CGRect?
        switch value {
        case .string(let text):
            let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }
            let numbers = parts.compactMap(Double.init)
            if parts.count == 4, numbers.count == 4 {
                rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            }
        case .object(let object):
            let x = object.double("x") ?? object.double("left")
            let y = object.double("y") ?? object.double("top")
            if let x, let y, let width = object.double("width"), let height = object.double("height") {
                rect = CGRect(x: x, y: y, width: width, height: height)
            }
        default:
            rect = nil
        }
        guard let rect, rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// A window reference (`WindowHandle`, a Window argument): a CGWindowID in decimal or `0x` hex text or as a number,
    /// else something only the AI tools' resolver knows ("w7").
    public enum WindowReference: Equatable, Sendable {
        case none
        case id(CGWindowID)
        case other(JSONValue)
    }

    public static func windowReference(_ value: JSONValue?) -> WindowReference {
        guard let value, !value.isNull else { return .none }
        if case .number(let number) = value {
            return number >= 0 && number <= Double(UInt32.max) && number == number.rounded() ? .id(CGWindowID(number)) : .other(value)
        }
        guard let text = value.asString?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return .none }
        if let decimal = UInt32(text) { return .id(decimal) }
        if text.lowercased().hasPrefix("0x"), let hex = UInt32(text.dropFirst(2), radix: 16) { return .id(hex) }
        return .other(value)
    }

    /// What `SelectedWindow` and `TargetWindow` hold for expressions: `${SelectedWindow.Title}` and the like.
    public static func windowValue(id: CGWindowID, title: String, app: String, pid: Int32, frame: CGRect) -> JSONValue {
        .object(["Id": .number(Double(id)), "Title": .string(title), "App": .string(app), "Pid": .number(Double(pid)),
                 "X": .number(Double(frame.minX)), "Y": .number(Double(frame.minY)),
                 "Width": .number(Double(frame.width)), "Height": .number(Double(frame.height))])
    }

    /// A delay as given, at most a minute (a recipe must not hang the capture).
    public static func clampedDelay(_ milliseconds: Int) -> Int {
        min(max(milliseconds, 0), 60_000)
    }
}
