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
    /// Tells this document apart from others, e.g. so elements pasted into the window they were copied from move a
    /// little (upstream `Surface.ID`).
    public let id = UUID()
    public private(set) var baseImage: CGImage
    public private(set) var annotations: [Annotation]
    /// Pixels per point of the capture.
    public private(set) var scale: CGFloat
    public var title: String
    public var captureDate: Date
    /// Where the image was opened from or last saved to.
    public var fileURL: URL?
    /// Changed since it was last saved, copied or printed.
    public private(set) var isModified: Bool
    /// The number of the first counter; the others count on from it (upstream `Surface.CounterStart`).
    public var counterStart = 1

    private struct State {
        var base: CGImage
        var annotations: [Annotation]
        var counterStart: Int

        func same(as other: State) -> Bool {
            base === other.base && annotations == other.annotations && counterStart == other.counterStart
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

    /// Starts over with another screenshot: no elements, no undo, not saved anywhere (upstream replaces the surface
    /// of a reused editor).
    public func reset(image: CGImage, scale: CGFloat, title: String, captureDate: Date = Date()) {
        guard depth == 0 else { return }
        baseImage = image
        self.scale = scale
        self.title = title
        self.captureDate = captureDate
        annotations = []
        counterStart = 1
        fileURL = nil
        undoStack.removeAll()
        redoStack.removeAll()
        isModified = true
    }

    private var current: State { State(base: baseImage, annotations: annotations, counterStart: counterStart) }

    private func restore(_ state: State) {
        baseImage = state.base
        annotations = state.annotations
        counterStart = state.counterStart
        isModified = true
    }

    // MARK: Elements

    public func annotation(_ id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    public func add(_ annotation: Annotation) {
        annotations.append(annotation.spanning(width: imageSize.width))
    }

    /// Replaces the element with the same id. A cut mark stays across the whole image, it only moves up and down.
    public func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation.spanning(width: imageSize.width)
    }

    public func remove(_ id: UUID) {
        annotations.removeAll { $0.id == id }
    }

    /// Adds elements on top of the others, in their order.
    public func add(_ elements: [Annotation]) {
        let width = imageSize.width
        annotations.append(contentsOf: elements.map { $0.spanning(width: width) })
    }

    /// The elements with one of `ids`, in drawing order (back to front).
    public func annotations(_ ids: Set<UUID>) -> [Annotation] {
        annotations.filter { ids.contains($0.id) }
    }

    public func remove(_ ids: Set<UUID>) {
        annotations.removeAll { ids.contains($0.id) }
    }

    /// Moves the elements with one of `ids` by `delta` (image pixels).
    public func move(_ ids: Set<UUID>, by delta: CGVector) {
        guard delta != .zero else { return }
        let width = imageSize.width
        for index in annotations.indices where ids.contains(annotations[index].id) {
            annotations[index].move(by: delta)
            annotations[index] = annotations[index].spanning(width: width)
        }
    }

    /// Copies of the elements with one of `ids`, with new ids, moved by `delta` and added on top
    /// (upstream `Surface.DuplicateSelectedElements`, which moves them by 10, 10). Returns the copies.
    @discardableResult
    public func duplicate(_ ids: Set<UUID>, offset delta: CGVector) -> [Annotation] {
        let copies = annotations(ids).map { original -> Annotation in
            var copy = original.withNewID()
            copy.move(by: delta)
            return copy
        }
        add(copies)
        return copies
    }

    public func bringToFront(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations.append(annotations.remove(at: index))
    }

    public func sendToBack(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations.insert(annotations.remove(at: index), at: 0)
    }

    /// Puts the elements with one of `ids` on top of all others, keeping their order (upstream `PullElementsToTop`).
    public func bringToFront(_ ids: Set<UUID>) {
        let moving = annotations.filter { ids.contains($0.id) }
        annotations = annotations.filter { !ids.contains($0.id) } + moving
    }

    /// Puts the elements with one of `ids` below all others, keeping their order (upstream `PushElementsToBottom`).
    public func sendToBack(_ ids: Set<UUID>) {
        let moving = annotations.filter { ids.contains($0.id) }
        annotations = moving + annotations.filter { !ids.contains($0.id) }
    }

    /// Whether one of the elements with `ids` has an unselected element above it (upstream `CanPullUp`).
    public func canBringForward(_ ids: Set<UUID>) -> Bool {
        let selected = annotations.indices.filter { ids.contains(annotations[$0].id) }
        guard !selected.isEmpty, selected.count < annotations.count else { return false }
        return selected.contains { $0 < annotations.count - selected.count }
    }

    /// Whether one of the elements with `ids` has an unselected element below it (upstream `CanPushDown`).
    public func canSendBackward(_ ids: Set<UUID>) -> Bool {
        let selected = annotations.indices.filter { ids.contains(annotations[$0].id) }
        guard !selected.isEmpty, selected.count < annotations.count else { return false }
        return selected.contains { $0 >= selected.count }
    }

    /// Moves the elements with `ids` one level up: each swaps with the unselected element just above it, so
    /// neighbours move up together (upstream `PullElementsUp`).
    public func bringForward(_ ids: Set<UUID>) {
        for i in annotations.indices.reversed() where ids.contains(annotations[i].id) {
            if i + 1 < annotations.count && !ids.contains(annotations[i + 1].id) { annotations.swapAt(i, i + 1) }
        }
    }

    /// Moves the elements with `ids` one level down (upstream `PushElementsDown`).
    public func sendBackward(_ ids: Set<UUID>) {
        for i in annotations.indices where ids.contains(annotations[i].id) {
            if i > 0 && !ids.contains(annotations[i - 1].id) { annotations.swapAt(i, i - 1) }
        }
    }

    /// The front-most element at `point` (image pixels).
    public func topmostAnnotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.last { $0.hitTest(point, scale: scale, tolerance: tolerance) }
    }

    /// The number a counter shows: counters are numbered in the order they were added, from `counterStart`, and
    /// renumber when one is removed (upstream `StepLabelContainer`, `Surface.CountStepLabels`).
    public func counterNumber(for id: UUID) -> Int? {
        var number = counterStart - 1
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
        moveAnnotations(by: CGVector(dx: -target.minX, dy: -target.minY))
        return true
    }

    /// Applies an effect of the Effects menu to the image (upstream `Surface.ApplyBitmapEffect`): the elements stay
    /// editable and move along when the image grows. Returns false when the effect could not be drawn.
    /// `seed` picks the torn edges.
    @discardableResult
    public func apply(_ effect: ImageEffect, seed: UInt64 = .random(in: .min ... .max)) -> Bool {
        guard let result = ImageEffects.apply(effect, to: baseImage, scale: scale, seed: seed) else { return false }
        baseImage = result.image
        moveAnnotations(by: result.offset)
        return true
    }

    /// Replaces the image with the result of an operation (resize, rotate, canvas change, …) and moves the elements
    /// by `offset`; `transform` maps old element positions to new ones when it is not a plain move (rotate, resize).
    @discardableResult
    public func replaceImage(with image: CGImage, offset: CGVector = .zero, transform: ((Annotation) -> Annotation)? = nil) -> Bool {
        baseImage = image
        if let transform {
            // Cut marks keep spanning the (new) image width.
            annotations = annotations.map { transform($0).spanning(width: imageSize.width) }
        } else {
            moveAnnotations(by: offset)
        }
        return true
    }

    private func moveAnnotations(by delta: CGVector) {
        let width = imageSize.width
        annotations = annotations.map {
            var moved = $0
            moved.move(by: delta)
            return moved.spanning(width: width)
        }
    }

    /// The image with all elements drawn on it, the way it is saved.
    public func flattened() -> CGImage {
        AnnotationRenderer.flatten(base: baseImage, annotations: annotations, scale: scale, counterStart: counterStart) ?? baseImage
    }
}
