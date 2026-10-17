// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import SwiftUI

/// The recipe editor's window: its keys are handled before the main menu (upstream RecipeEditorWindow.xaml:20-31 with
/// ⌘ for Ctrl): ⌘N new recipe, ⌘O open, ⌘S save, ⇧⌘S save as, ⌘R test run, ⇧⌘M the recipe manager (⌘M stays
/// Minimize), ⌘Y redo; ⌘Z / ⇧⌘Z through Edit › Undo and Redo. The File menu's image commands act on image editors only.
final class RecipeEditorWindow: NSWindow {
    weak var model: RecipeEditorModel?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let model, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, key) {
        case ([.command], "n"): Task { await model.newRecipeAsking() }
        case ([.command], "o"): Task { await model.openFileAsking() }
        case ([.command], "s"): Task { await model.save() }
        case ([.command, .shift], "s"): Task { await model.saveAs() }
        case ([.command], "r"): Task { await model.testRun() }
        case ([.command, .shift], "m"): RecipeManagerService.show(selecting: model.recipe?.id)
        case ([.command], "y"): redo(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Typing in a text field undoes the typing first; otherwise the recipe's history.
    @objc func undo(_ sender: Any?) {
        if let text = firstResponder as? NSTextView, text.undoManager?.canUndo == true {
            text.undoManager?.undo()
            return
        }
        makeFirstResponder(nil)
        model?.undo()
    }

    @objc func redo(_ sender: Any?) {
        if let text = firstResponder as? NSTextView, text.undoManager?.canRedo == true {
            text.undoManager?.redo()
            return
        }
        makeFirstResponder(nil)
        model?.redo()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            return (firstResponder as? NSTextView)?.undoManager?.canUndo == true || model?.canUndo == true
        case #selector(redo(_:)):
            return (firstResponder as? NSTextView)?.undoManager?.canRedo == true || model?.canRedo == true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    /// ⌫ / ⌦ delete the selected step or connection while the step list has the focus (upstream Delete/Backspace).
    override func keyDown(with event: NSEvent) {
        let code = Int(event.keyCode)
        if code == kVK_Delete || code == kVK_ForwardDelete, !(firstResponder is NSTextView) {
            model?.deleteSelection()
            return
        }
        super.keyDown(with: event)
    }
}

/// One recipe editor window, reused (upstream opens one editor window).
@MainActor
final class RecipeEditorWindowController: NSWindowController, NSWindowDelegate {
    private(set) static var shared: RecipeEditorWindowController?

    let model: RecipeEditorModel
    private var closing = false

    init(model: RecipeEditorModel) {
        self.model = model
        let window = RecipeEditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                                        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        window.model = model
        window.title = "Recipe Editor"
        window.minSize = NSSize(width: 860, height: 540)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RecipeEditorView(model: model))
        window.center()
        window.setFrameAutosaveName("RecipeEditor")
        super.init(window: window)
        window.delegate = self
        model.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The window, created on first use, brought to the front.
    static func show(_ configure: (RecipeEditorModel) -> Void = { _ in }) -> RecipeEditorWindowController {
        let controller = shared ?? RecipeEditorWindowController(model: RecipeEditorModel(environment: .live))
        shared = controller
        controller.model.observeLibrary()
        configure(controller.model)
        if let window = controller.window {
            AuxiliaryWindows.opened(window)
            controller.model.updateWindow()
            controller.showWindow(nil)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        return controller
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closing || !model.isDirty { return true }
        Task { @MainActor in
            if await model.confirmDiscardChanges() {
                closing = true
                sender.close()
                closing = false
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        AuxiliaryWindows.closed(window)
        model.stopObserving()
    }
}
