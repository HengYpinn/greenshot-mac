// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The image in an editor window and the elements on it (upstream `Surface`), with undo and redo.
///
/// A change is wrapped in `beginChange()` / `endChange()` (or `change { }`); a gesture like dragging an element
/// keeps the change open from mouse down to mouse up, so it is one undo step. A change that changed nothing
/// leaves no undo step.
public final class EditorDocument {
    public private(set) var baseImage: CGImage
    public private(set) var annotations: [Annotation]
    /// Pixels per point of the capture.
    public let scale: CGFloat
    public var title: String
    public var captureDate: Date
    /// Where the image was opened from or last saved to.
    public var fileURL: URL?
    /// Changed since it was last saved, copied or printed.
    public private(set) var isModified: Bool

    private struct State {
        var base: CGImage
        var annotations: [Annotation]

        func same(as other: State) -> Bool {
            base === other.base && annotations == other.annotations
        }
    }

    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private var pending: State?
    private var depth = 0
    private let undoLimit = 100

    public init(image: CGImage, scale: CGFloat, title: String, captureDate: Date = Date(), fileURL: URL? = nil, isModified: Bool = true) {
        baseImage = image
        annotations = []
        self.scale = scale
        self.title = title
        self.captureDate = captureDate
        self.fileURL = fileURL
        self.isModified = isModified
    }

    public var imageSize: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Changes

    public func beginChange() {
        if depth == 0 { pending = current }
        depth += 1
    }

    public func endChange() {
        guard depth > 0 else { return }
        depth -= 1
        guard depth == 0, let before = pending else { return }
        pending = nil
        guard !before.same(as: current) else { return }
        undoStack.append(before)
        if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        redoStack.removeAll()
        isModified = true
    }

    public func change(_ body: () -> Void) {
        beginChange()
        body()
        endChange()
    }

    public func undo() {
        guard depth == 0, let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        restore(previous)
    }

    public func redo() {
        guard depth == 0, let next = redoStack.popLast() else { return }
        undoStack.append(current)
        restore(next)
    }

    public func markSaved() {
        isModified = false
    }

    private var current: State { State(base: baseImage, annotations: annotations) }

    private func restore(_ state: State) {
        baseImage = state.base
        annotations = state.annotations
        isModified = true
    }

    // MARK: Elements

    public func annotation(_ id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    public func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    public func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    public func remove(_ id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    public func bringToFront(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations.append(annotations.remove(at: index))
    }

    public func sendToBack(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations.insert(annotations.remove(at: index), at: 0)
    }

    /// The front-most element at `point` (image pixels).
    public func topmostAnnotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.last { $0.hitTest(point, scale: scale, tolerance: tolerance) }
    }

    /// The number a counter shows: counters are numbered in the order they were added, and renumber
    /// when one is removed (upstream `StepLabelContainer`).
    public func counterNumber(for id: UUID) -> Int? {
        var number = 0
        for annotation in annotations where annotation.kind == .counter {
            number += 1
            if annotation.id == id { return number }
        }
        return nil
    }

    /// Cuts the image to `rect` (image pixels) and moves the elements along. Returns false when nothing is left.
    @discardableResult
    public func crop(to rect: CGRect) -> Bool {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let target = rect.standardized.integral.intersection(bounds)
        guard !target.isEmpty, target != bounds, let cropped = baseImage.cropping(to: target) else { return false }
        baseImage = cropped
        let delta = CGVector(dx: -target.minX, dy: -target.minY)
        annotations = annotations.map {
            var moved = $0
            moved.move(by: delta)
            return moved
        }
        return true
    }

    /// The image with all elements drawn on it, the way it is saved.
    public func flattened() -> CGImage {
        AnnotationRenderer.flatten(base: baseImage, annotations: annotations, scale: scale) ?? baseImage
    }
}
