// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Upstream `EffectCaptureStep`: one of the image effects on the capture, through the editor's operations so the
/// annotations move along. Sizes are points (multiplied by the capture's pixels per point, decision D2). An effect
/// that can't be applied is logged and the flow goes on, like upstream.
struct EffectExecutor: RecipeStepExecutor {
    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard var payload = context.payload else {
            context.log("Effect skipped: there is no image.")
            return
        }
        let document = EditorDocument(image: payload.image, scale: payload.scale, title: payload.title)
        document.addOpened(payload.annotations)
        let name = step.string("Effect")?.trimmingCharacters(in: .whitespaces) ?? "Border"
        let applied = Self.apply(name.isEmpty ? "Border" : name, step, document, scale: payload.scale)
        guard applied else {
            context.log("Warning: the effect '\(name)' could not be applied.")
            log.warn("Recipe '\(context.recipe.id)': the effect '\(name)' could not be applied.")
            return
        }
        payload.image = document.baseImage
        payload.annotations = document.annotations
        context.payload = payload
        context.log("Applied effect '\(name)'")
    }

    static func apply(_ name: String, _ step: RecipeStepInvocation, _ document: EditorDocument, scale: CGFloat) -> Bool {
        func pixels(_ points: Int) -> Int { ImageOperations.pixels(points, scale: scale) }
        switch name.lowercased() {
        case "border":
            let width = max(1, step.int("Width") ?? 2)
            let color = step.color("Color") ?? .black
            guard let result = RecipeEffects.border(document.baseImage, width: CGFloat(pixels(width)), color: color) else { return false }
            return document.replaceImage(with: result.image, offset: result.offset)
        case "dropshadow":
            let defaults = DropShadowSettings()
            let settings = DropShadowSettings(darkness: step.double("Darkness") ?? defaults.darkness, size: step.int("ShadowSize") ?? defaults.size,
                                              offsetX: step.int("ShadowOffsetX") ?? defaults.offsetX, offsetY: step.int("ShadowOffsetY") ?? defaults.offsetY)
            return document.apply(.dropShadow, dropShadow: settings, tornEdge: TornEdgeSettings())
        case "tornedge":
            return document.apply(.tornEdge, dropShadow: DropShadowSettings(), tornEdge: tornEdgeSettings(step))
        case "invert":
            return document.apply(.invert)
        case "grayscale":
            return document.apply(.grayscale)
        case "monochrome":
            let threshold = UInt8(min(max(step.int("Threshold") ?? 128, 0), 255))
            return document.transformImage { ImageEffects.monochrome($0, threshold: threshold) }
        case "adjust":
            let brightness = step.double("Brightness") ?? 1
            let contrast = step.double("Contrast") ?? 1
            let gamma = step.double("Gamma") ?? 1
            return document.transformImage { ImageEffects.adjust($0, brightness: brightness, contrast: contrast, gamma: gamma) }
        case "rotate":
            switch step.int("Angle") ?? 90 {
            case 90: return document.rotateImage(clockwise: true)
            case -90, 270: return document.rotateImage(clockwise: false)
            case 180, -180: return document.rotateImage(clockwise: true) && document.rotateImage(clockwise: true)
            default: return false
            }
        case "resize":
            return resize(step, document, scale: scale)
        case "resizecanvas":
            let margin = step.int("Margin") ?? 0
            let left = pixels(step.int("Left") ?? margin)
            let right = pixels(step.int("Right") ?? margin)
            let top = pixels(step.int("Top") ?? margin)
            let bottom = pixels(step.int("Bottom") ?? margin)
            let background = (step.color("BackgroundColor") ?? step.color("Color"))?.cgColor
            return document.resizeCanvas(left: left, right: right, top: top, bottom: bottom, background: background)
        case "reducecolors":
            let colors = min(max(step.int("Colors") ?? 256, 2), 256)
            return document.transformImage { ImageEffects.reduceColors($0, to: colors) }
        case "removetransparency":
            let color = step.color("Color") ?? .white
            // An image without transparency stays as it is.
            return !ImageOperations.hasTransparency(document.baseImage) || document.removeTransparency(color: color.cgColor)
        default:
            return false
        }
    }

    /// Upstream `ResizeEffect` with `Percentage`, or `Width` / `Height` (points), keeping the aspect ratio by default.
    private static func resize(_ step: RecipeStepInvocation, _ document: EditorDocument, scale: CGFloat) -> Bool {
        let current = CGSize(width: document.baseImage.width, height: document.baseImage.height)
        if let percentage = step.double("Percentage"), percentage > 0 {
            let factor = CGFloat(percentage / 100)
            return document.resizeImage(to: CGSize(width: current.width * factor, height: current.height * factor))
        }
        let width = CGFloat(step.int("Width") ?? 0) * scale
        let height = CGFloat(step.int("Height") ?? 0) * scale
        guard width > 0 || height > 0 else { return false }
        if step.bool("MaintainAspectRatio") ?? true {
            let factor = width > 0 ? width / current.width : height / current.height
            return document.resizeImage(to: CGSize(width: current.width * factor, height: current.height * factor))
        }
        return document.resizeImage(to: CGSize(width: width > 0 ? width : current.width, height: height > 0 ? height : current.height))
    }

    /// Upstream `TornEdgeEffect` from the parameters; `Edges` is four bools (top, right, bottom, left) or a text naming them.
    private static func tornEdgeSettings(_ step: RecipeStepInvocation) -> TornEdgeSettings {
        var settings = TornEdgeSettings()
        settings.toothHeight = step.int("ToothHeight") ?? settings.toothHeight
        settings.horizontalToothRange = step.int("HorizontalToothRange") ?? settings.horizontalToothRange
        settings.verticalToothRange = step.int("VerticalToothRange") ?? settings.verticalToothRange
        settings.shadow = step.bool("GenerateShadow") ?? settings.shadow
        settings.shadowSize = step.int("ShadowSize") ?? settings.shadowSize
        settings.shadowDarkness = step.double("Darkness") ?? settings.shadowDarkness
        if let edges = step.value("Edges") {
            if let flags = edges.arrayValue?.compactMap(\.asBool), flags.count == 4 {
                settings.top = flags[0]
                settings.right = flags[1]
                settings.bottom = flags[2]
                settings.left = flags[3]
            } else if let text = edges.stringValue?.lowercased(), !text.isEmpty {
                settings.top = text.contains("top")
                settings.right = text.contains("right")
                settings.bottom = text.contains("bottom")
                settings.left = text.contains("left")
            }
        }
        return settings
    }
}

/// Image operations recipes need beyond the editor's.
enum RecipeEffects {
    /// Upstream `ImageHelper.CreateBorder` with a width and a color: a bigger image with a line around the original.
    static func border(_ image: CGImage, width: CGFloat, color: RGBAColor) -> EffectResult? {
        let size = CGSize(width: CGFloat(image.width) + width * 2, height: CGFloat(image.height) + width * 2)
        guard let context = ImageEffects.makeContext(size) else { return nil }
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.stroke(CGRect(origin: .zero, size: size).insetBy(dx: width / 2, dy: width / 2))
        context.draw(image, in: CGRect(x: width, y: width, width: CGFloat(image.width), height: CGFloat(image.height)))
        return ImageEffects.result(context, offset: CGVector(dx: width, dy: width))
    }
}

private let log = Log("Recipes")
