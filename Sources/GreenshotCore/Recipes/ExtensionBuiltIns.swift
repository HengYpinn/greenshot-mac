// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The automatic steps Greenshot brings (upstream `Greenshot/Recipes/BuiltInExtensions.cs`): caption, border and drop
/// shadow on every capture, all switched off until the user switches them on (Settings › Recipes or Quick Settings).
/// They run per destination (BeforeDestination), so the user can pick the destinations they are for, e.g. a border only
/// for email. Built only from existing steps. Upstream's texts are language keys; these are their English texts.
public enum RecipeBuiltInExtensions {
    public static let borderId = "ext_border"
    public static let dropShadowId = "ext_dropshadow"
    public static let captionId = "ext_caption"

    /// Order on the slot: the caption bar is part of the image, the border goes around it, the shadow falls outside the border.
    public static let captionOrder = 100
    public static let borderOrder = 200
    public static let dropShadowOrder = 300

    public static var all: [CaptureRecipe] { [border(), dropShadow(), caption()] }

    /// A border around the capture (upstream #1239, #1016, #696, #591): width and colour.
    public static func border() -> CaptureRecipe {
        var ext = extensionRecipe(borderId, name: "Border", description: "Adds a border around the capture before it is exported.",
                                  order: borderOrder)
        ext.options = [onOff("Add a border"), number("width", "Width (px)", 2, 1, 50), color("color", "Color", "#000000")]
        ext.nodes = [RecipeNode(id: "border", stepType: WellKnownStepType.effect, name: "Border",
                                parameters: ["Effect": .string("Border"), "Width": .string("${option.width}"), "Color": .string("${option.color}")])]
        ext.flow = RecipeFlow(startNodes: ["border"])
        return ext
    }

    /// A drop shadow (upstream #591): size, darkness and offset.
    public static func dropShadow() -> CaptureRecipe {
        var ext = extensionRecipe(dropShadowId, name: "Drop shadow", description: "Adds a drop shadow to the capture before it is exported.",
                                  order: dropShadowOrder)
        var darkness = RecipeOption(key: "darkness", type: .decimal, defaultValue: .number(0.6))
        darkness.min = 0.1
        darkness.max = 1
        darkness.label = "Darkness"
        darkness.enabledWhen = RecipeExtensionNames.enabledOptionKey
        ext.options = [onOff("Add a drop shadow"), number("size", "Size (px)", 7, 1, 50), darkness, number("offset", "Offset (px)", -1, -20, 20)]
        ext.nodes = [RecipeNode(id: "shadow", stepType: WellKnownStepType.effect, name: "Drop shadow",
                                parameters: ["Effect": .string("DropShadow"), "ShadowSize": .string("${option.size}"),
                                             "Darkness": .string("${option.darkness}"), "ShadowOffsetX": .string("${option.offset}"),
                                             "ShadowOffsetY": .string("${option.offset}")])]
        ext.flow = RecipeFlow(startNodes: ["shadow"])
        return ext
    }

    /// A bar above or below the capture with a text, by default the date and time (upstream #906): text, position, font
    /// size and colours.
    public static func caption() -> CaptureRecipe {
        let barHeight = "${option.fontSize * 2}"
        var ext = extensionRecipe(captionId, name: "Caption",
                                  description: "Adds a bar with a text, for example the date and time, above or below the capture.",
                                  order: captionOrder)
        var text = RecipeOption(key: "text", type: .string, defaultValue: .string("${now:yyyy-MM-dd HH:mm:ss}"))
        text.format = RecipeOption.formatTemplate
        text.label = "Text"
        text.description = "The text of the caption: ${now:yyyy-MM-dd HH:mm:ss} is the date and time, ${user.username} your user name."
        text.enabledWhen = RecipeExtensionNames.enabledOptionKey
        var position = RecipeOption(key: "position", type: .enumeration, defaultValue: .string("Bottom"))
        position.label = "Position"
        position.enabledWhen = RecipeExtensionNames.enabledOptionKey
        position.choices = [RecipeOptionChoice(value: "Top", label: "Above the capture"),
                            RecipeOptionChoice(value: "Bottom", label: "Below the capture")]
        ext.options = [onOff("Add a caption"), text, position, number("fontSize", "Font size", 12, 6, 72),
                       color("textColor", "Text color", "#000000"), color("barColor", "Bar color", "#FFFFFF")]

        func bar(_ id: String, _ side: String) -> RecipeNode {
            var parameters: JSONObject = ["Effect": .string("ResizeCanvas")]
            parameters[side] = .string(barHeight)
            parameters["BackgroundColor"] = .string("${option.barColor}")
            return RecipeNode(id: id, stepType: WellKnownStepType.effect, name: "Caption bar", parameters: parameters)
        }
        func label(_ id: String, _ anchor: String) -> RecipeNode {
            var parameters: JSONObject = ["Type": .string("Text"), "Text": .string("${option.text}"),
                                          "FontSize": .string("${option.fontSize}"), "LineColor": .string("${option.textColor}"),
                                          "Shadow": .bool(false), "TextAlign": .string("Center"), "Left": .number(0),
                                          "Width": .string("${payload.width}"), "Height": .string(barHeight),
                                          "VerticalAnchor": .string(anchor)]
            parameters[anchor] = .number(0)
            return RecipeNode(id: id, stepType: WellKnownStepType.annotation, name: "Caption text", parameters: parameters)
        }
        let branches: [JSONValue] = [
            .object(["Key": .string("Top"), "Expression": .string("${option.position == 'Top'}")]),
            .object(["Key": .string("Bottom"), "Expression": .string("else")])
        ]
        ext.nodes = [RecipeNode(id: "position", stepType: WellKnownStepType.conditional, name: "Caption position",
                                parameters: ["Branches": .array(branches)]),
                     bar("bar_top", "Top"), label("text_top", "Top"), bar("bar_bottom", "Bottom"), label("text_bottom", "Bottom")]
        var flow = RecipeFlow(startNodes: ["position"])
        flow.conditionalTransitions = [ConditionalTransition(from: "position", branch: "Top", to: "bar_top"),
                                       ConditionalTransition(from: "position", branch: "Bottom", to: "bar_bottom")]
        flow.addTransition(from: "bar_top", to: "text_top")
        flow.addTransition(from: "bar_bottom", to: "text_bottom")
        ext.flow = flow
        return ext
    }

    private static func extensionRecipe(_ id: String, name: String, description: String, order: Int) -> CaptureRecipe {
        var ext = CaptureRecipe(id: id, name: name, description: description)
        ext.kind = .extension
        ext.extends = ExtensionTarget(recipes: [RecipeExtensionNames.targetCaptures], slot: RecipeSlots.beforeDestination, order: order)
        return ext
    }

    private static func onOff(_ label: String) -> RecipeOption {
        var option = RecipeOption(key: RecipeExtensionNames.enabledOptionKey, type: .boolean, defaultValue: .bool(false))
        option.label = label
        option.quickSettings = true
        return option
    }

    private static func number(_ key: String, _ label: String, _ value: Int, _ min: Int, _ max: Int) -> RecipeOption {
        var option = RecipeOption(key: key, type: .integer, defaultValue: .number(Double(value)))
        option.min = Double(min)
        option.max = Double(max)
        option.label = label
        option.enabledWhen = RecipeExtensionNames.enabledOptionKey
        return option
    }

    private static func color(_ key: String, _ label: String, _ value: String) -> RecipeOption {
        var option = RecipeOption(key: key, type: .color, defaultValue: .string(value))
        option.label = label
        option.enabledWhen = RecipeExtensionNames.enabledOptionKey
        return option
    }
}
