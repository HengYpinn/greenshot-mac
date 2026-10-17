// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Upstream `AnnotationStep`: adds editable elements to the capture, one per entry of `Annotations` or one described by
/// the node's own parameters. It evaluates its parameters itself (once), with the capture's size in points as
/// `width`/`w`, `height`/`h`, `payload.width`, `surface.width` (and the heights), so `"${width - 120}"` works.
struct AnnotationExecutor: RecipeStepExecutor {
    let cursorImages: (any RecipeCursorImageProviding)?

    func execute(_ step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard var payload = context.payload else {
            context.log("AnnotationStep skipped: visual payload is null.")
            return
        }
        let metrics = payload.metrics
        let width = JSONValue.number(metrics.width)
        let height = JSONValue.number(metrics.height)
        let scope = context.scope(extraVariables: ["payload.width": width, "payload.height": height, "surface.width": width,
                                                   "surface.height": height, "width": width, "w": width, "height": height, "h": height])
        let factory = RecipeAnnotationFactory(imageSize: CGSize(width: payload.image.width, height: payload.image.height),
                                              scale: payload.scale)
        var elements: [Annotation] = []
        var crop: CGRect?
        for raw in Self.configurations(step.parameters) {
            let parameters = AnnotationParameters(context.evaluator.resolveParameters(raw, in: scope))
            let cursor = await pointerPicture(parameters, context)
            switch factory.make(parameters, cursor: cursor) {
            case .element(let element):
                elements.append(element)
            case .crop(let box):
                crop = box
            case .skipped(let reason):
                log.warn("Recipe '\(context.recipe.id)': an annotation of node '\(step.node.id)' was skipped: \(reason).")
                context.log("Warning: annotation skipped: \(reason).")
            }
        }
        guard !elements.isEmpty || crop != nil else { return }
        payload.annotations += elements
        if let crop {
            let document = EditorDocument(image: payload.image, scale: payload.scale, title: payload.title)
            document.addOpened(payload.annotations)
            if document.crop(to: crop) {
                payload.image = document.baseImage
                payload.annotations = document.annotations
                context.log("AnnotationStep cropped the capture.")
            } else {
                context.log("Warning: the crop of the annotation is empty or covers the whole capture.")
            }
        }
        context.payload = payload
        if !elements.isEmpty {
            context.log("AnnotationStep added \(elements.count) element(s) to surface.")
        }
    }

    /// The entries of `Annotations` (objects only, like upstream), else the node's parameters as one annotation.
    static func configurations(_ parameters: JSONObject) -> [JSONObject] {
        guard let list = parameters["Annotations"], !list.isNull else { return [parameters] }
        return list.arrayValue?.compactMap(\.objectValue) ?? []
    }

    /// The picture of a `Cursor` annotation's preset (`CursorName`, or the arrow without a file), from the app.
    private func pointerPicture(_ p: AnnotationParameters, _ context: RecipeFlowContext) async -> (image: CGImage, hotSpot: CGPoint)? {
        guard recipeEquals(p.text("Type")?.trimmingCharacters(in: .whitespaces) ?? "", "Cursor"), p.text("ImageData") == nil else {
            return nil
        }
        let name = p.text("CursorName")
        guard name != nil || p.text("FilePath") == nil else { return nil }
        guard let cursorImages else {
            context.log("Warning: pointer pictures are not available here.")
            return nil
        }
        return await cursorImages.cursorImage(named: name?.trimmingCharacters(in: .whitespaces) ?? "Arrow")
    }
}

private let log = Log("Recipes")
