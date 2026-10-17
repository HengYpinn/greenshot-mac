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
    /// binds) or an object `{x, y, width, height}` (also left/top). Nil when it isn't one or is empty.
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

    /// What the variable `SelectedWindow` holds: the window's id (CGWindowID), title, app, process id and frame (Quartz
    /// global points), as an object (upstream holds the window itself).
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

// MARK: Captures started from the command line

/// A recipe started by greenshot-cli asks before it takes something from the screen without the user on the capture
/// screen (Mac only; `AutomationConsent`): any local program can run greenshot-cli, so the app's screen recording
/// permission must not be borrowed silently (CWE-441). RUN_RECIPE puts it into the run as the host object
/// `objectKey`; the Source step asks it when the capture happens, for what the flow really does (a region from a
/// variable, a capture whose path to an export has no selection), so a question decided before the run can't miss it.
public final class RecipeCaptureConsent: @unchecked Sendable {
    public static let objectKey = "CaptureConsent"

    private let lock = NSLock()
    private var granted: Set<String>
    private let ask: @Sendable (String) async -> Bool

    /// - Parameters:
    ///   - granted: what the user already allowed for this run (RUN_RECIPE's question before the start).
    ///   - ask: shows the question for a subject ("a screenshot of the whole screen"); true when allowed.
    public init(granted: [String] = [], ask: @escaping @Sendable (String) async -> Bool) {
        self.granted = Set(granted)
        self.ask = ask
    }

    /// Whether the run may take `subject`; asks once per subject.
    public func allows(_ subject: String) async -> Bool {
        if lock.withLock({ granted.contains(subject) }) { return true }
        guard await ask(subject) else { return false }
        lock.withLock { _ = granted.insert(subject) }
        return true
    }
}

extension RecipeSourceValues {
    /// What a Source takes from the screen without the user selecting it, in `AutomationConsent`'s words; nil when the
    /// user makes the capture on the capture screen (`selectionFollows`) or it doesn't come from the screen.
    /// - Parameters:
    ///   - named: a Window source with a window given (WindowHandle, title, process, TargetWindow).
    ///   - region: a region was given (PreSuppliedRegion).
    public static func unattendedSubject(_ type: SourceType, region: Bool, named: Bool, selectionFollows: Bool) -> String? {
        if region { return "a screenshot of a region" }
        switch type {
        case .fullScreen: return "a screenshot of the whole screen"
        case .activeWindow: return "a screenshot of the active window"
        case .lastRegion: return "a screenshot of the last captured region"
        case .window where named: return "a screenshot of a window"
        case .region, .window, .textOcr: return selectionFollows ? nil : "a screenshot of the whole screen"
        case .clipboard, .file, .currentEditor, .extension: return nil
        }
    }

    /// Whether every way on from `nodeId` reaches a switched-on InteractiveSelection before the flow ends or leaves the
    /// recipe: only then does the user choose what a screen Source's picture of every display becomes. A selection
    /// switched on by an expression, an error route to another recipe or a loop without a selection count as none.
    public static func selectionFollows(_ recipe: CaptureRecipe, from nodeId: String) -> Bool {
        let transitions = recipe.flow.unifiedTransitions
        var known: [String: Bool] = [:]
        var onPath = Set<String>()
        func next(_ id: String) -> [String]? {
            guard let node = recipe.node(id) else { return [] }
            if let recipeId = node.onErrorRecipeId, !recipeId.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            var targets = transitions[id.lowercased()] ?? []
            if let errorNode = node.onErrorNodeId, !errorNode.isEmpty { targets.append(errorNode) }
            for transition in recipe.flow.errorTransitions {
                let from = transition.from ?? "*"
                guard from == "*" || from.isEmpty || recipeEquals(from, id) else { continue }
                if let to = transition.to, !to.isEmpty { targets.append(to) }
                if let other = transition.targetRecipeId, !other.isEmpty { return nil }
            }
            return targets
        }
        func reaches(_ id: String) -> Bool {
            let key = id.lowercased()
            if let result = known[key] { return result }
            // Back on the way here: a loop that can go round without a selection.
            guard onPath.insert(key).inserted else { return false }
            defer { onPath.remove(key) }
            var result = false
            if let targets = next(id), !targets.isEmpty {
                result = targets.allSatisfy { target in
                    if let node = recipe.node(target), recipeEquals(node.stepType, WellKnownStepType.interactiveSelection),
                       node.enabled == .value(true) {
                        return true
                    }
                    return reaches(target)
                }
            }
            known[key] = result
            return result
        }
        return reaches(nodeId)
    }
}
