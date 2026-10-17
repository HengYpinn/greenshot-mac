// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// One capture screen at a time, and quitting while flows run.
extension RecipeRuntime {
    static let selectionOpen = "The capture screen is already open or about to open."

    /// Whether a flow will show the capture screen and hasn't closed it yet. A flow's capture screen opens only after
    /// its approval check, its capture delay and the freeze of the displays, so the runner's own check at the start
    /// can't see it; the app's own captures (`CaptureCoordinator.run`) ask this too.
    var isSelectionReserved: Bool { !selectionReservations.isEmpty }

    /// Starts a flow with `start`; a recipe that selects on the capture screen is not started while another flow or a
    /// capture of the app will show it: the open one comes to the front and the Mac beeps, as for a second capture
    /// (before wave 4 the app's `busy` did this). A started one holds the capture screen until its selection ended or
    /// the flow did.
    func launch(_ recipe: CaptureRecipe, _ start: () -> RecipeFlowHandle?) -> RecipeFlowHandle? {
        let selects = recipe.firstNode(ofType: WellKnownStepType.interactiveSelection) != nil
        if selects, isSelectionReserved || CaptureOverlayController.isShowing || app.capture.isBusy {
            log.info("Not starting recipe '\(recipe.id)': \(Self.selectionOpen)")
            CaptureOverlayController.bringToFront()
            NSSound.beep()
            return nil
        }
        guard let handle = start() else { return nil }
        if selects {
            selectionReservations.insert(handle.id)
            Task { @MainActor [weak self] in
                _ = await handle.result
                self?.releaseSelection(of: handle.id)
            }
        }
        return handle
    }

    /// The flow's selection ended (the InteractiveSelection step): another capture screen may open.
    func releaseSelection(of flowId: UUID) {
        selectionReservations.remove(flowId)
    }

    /// Quit (`AppDelegate.applicationShouldTerminate`): true when it may go on. Flows that still run are stopped by a
    /// quit; one that waits for the user (a prompt, the destination flyout) holds the only copy of its capture, and one
    /// that exports loses what it hasn't exported yet, so the user is asked first.
    func confirmQuit() -> Bool {
        let running = runner.running
        guard !running.isEmpty else { return true }
        let waiting = running.compactMap { handle in flowStates[handle.id]?.waitsFor.map { (name: handle.recipeName, what: $0) } }
        let alert = NSAlert()
        alert.alertStyle = .warning
        let count = running.count
        alert.messageText = count == 1 ? String(localized: "A recipe is still running") : String(localized: "\(count) recipes are still running")
        if let first = waiting.first {
            let name = first.name
            switch first.what {
            case .answer(let prompt):
                alert.informativeText = String(localized: "“\(name)” waits for your answer to “\(prompt)”. If you quit now, its capture is lost.")
            case .destination:
                alert.informativeText = String(localized: "“\(name)” waits for you to choose where its capture goes. If you quit now, its capture is lost.")
            }
        } else {
            let name = running[0].recipeName
            alert.informativeText = String(localized: "“\(name)” hasn't finished. If you quit now, what it hasn't exported yet is lost.")
        }
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
