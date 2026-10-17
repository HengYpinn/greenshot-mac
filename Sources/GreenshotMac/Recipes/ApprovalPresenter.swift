// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

private let log = Log("Recipes")

/// The approval window (RCP-193, upstream `RecipeApprovalWindow`): the library's approver (`RecipeRuntime.approver`
/// forwards to it). One window at a time: the files read at launch, the file monitor and a run's check of a changed file
/// can ask at once, so the requests wait for each other. Default-deny: closing the window, Esc or "Reject / Block" means
/// no. It never opens the recipe editor itself: "Open in the recipe editor after saving" is returned in the decision for
/// the code that writes the file.
@MainActor
final class RecipeApprovalPresenter: RecipeApprover {
    static let shared = RecipeApprovalPresenter()

    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var current: RecipeApprovalWindowController?

    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision? {
        await present(request)
    }

    func showValidationError(_ request: RecipeApprovalRequest) async {
        var shown = request
        shown.mode = .validationError
        _ = await present(shown)
    }

    private func present(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision? {
        await acquire()
        defer { release() }
        let name = request.recipe?.name ?? request.fileURL?.lastPathComponent ?? "recipe"
        log.info("Asking about recipe '\(name)' (\(request.isReadOnly ? "details" : request.mode.rawValue))")
        let decision: RecipeApprovalDecision? = await withCheckedContinuation { continuation in
            let controller = RecipeApprovalWindowController(request: request) { decision in
                continuation.resume(returning: decision)
            }
            current = controller
            controller.show()
        }
        current = nil
        if !request.isReadOnly, request.mode != .validationError {
            log.info(decision?.isRevoked == true ? "The user revoked the approval of '\(name)'"
                     : decision?.approval != nil ? "The user approved '\(name)'" : "The user didn't approve '\(name)'")
        }
        return decision
    }

    private func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// The window of one request. Closing it answers nil (rejected; in a review: kept as it is).
@MainActor
final class RecipeApprovalWindowController: NSWindowController, NSWindowDelegate {
    private let model: RecipeApprovalModel
    private var completion: ((RecipeApprovalDecision?) -> Void)?

    init(request: RecipeApprovalRequest, completion: @escaping (RecipeApprovalDecision?) -> Void) {
        model = RecipeApprovalModel(request: request)
        self.completion = completion
        let hosting = NSHostingController(rootView: RecipeApprovalView(model: model))
        let size = NSSize(width: 680, height: 760)
        let window = KeyHandlingWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
                                       backing: .buffered, defer: true)
        window.contentViewController = hosting
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: 560, height: 460)
        window.title = model.sheet.windowTitle
        window.isReleasedWhenClosed = false
        // Upstream's window stays on top (Topmost) and comes to whatever Space the user is on.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        window.delegate = self
        model.onFinish = { [weak self] decision in self?.finish(decision) }
        model.confirm = { [weak self] title, text, buttons in
            await self?.confirm(title: title, text: text, buttons: buttons) ?? 0
        }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func show() {
        guard let window else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let frame = window.frame
            window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: max(visible.minY, visible.midY - frame.height / 2)))
        }
        // Approve waits a moment when the window came up on its own, before the app is activated for it (S-N2).
        if RecipeApprovalSheet.needsArmingDelay(model.sheet.request, appWasActive: NSApp.isActive) {
            model.isArmed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + RecipeApprovalSheet.armingDelay) { [weak model] in
                model?.isArmed = true
            }
        }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        AuxiliaryWindows.opened(window)
    }

    private func finish(_ decision: RecipeApprovalDecision?) {
        guard let completion else { return }
        self.completion = nil
        window?.close()
        completion(decision)
    }

    func windowWillClose(_ notification: Notification) {
        if let window { AuxiliaryWindows.closed(window) }
        // Closed with the close button or Esc: nothing approved, nothing changed.
        guard let completion else { return }
        self.completion = nil
        completion(nil)
    }

    /// A question on the window; answers the index of the button (the first one is the default).
    private func confirm(title: String, text: String, buttons: [String]) async -> Int {
        guard let window else { return 0 }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = text
        for button in buttons { alert.addButton(withTitle: button) }
        let response = await withCheckedContinuation { (continuation: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}

/// What the window shows and does: `RecipeApprovalSheet` (Core) with the switches as the user sets them.
@MainActor
final class RecipeApprovalModel: ObservableObject {
    enum Overlay: Equatable {
        case json
        case changes
    }

    @Published var sheet: RecipeApprovalSheet
    @Published var openInEditor = false
    @Published var overlay: Overlay?
    @Published var changedLinesOnly = true
    /// False for a moment after the window came up on its own: Approve can't be clicked yet.
    @Published var isArmed = true
    var onFinish: ((RecipeApprovalDecision?) -> Void)?
    /// Title, text, buttons (the first is the default) -> the index of the button clicked.
    var confirm: ((String, String, [String]) async -> Int)?

    init(request: RecipeApprovalRequest) {
        sheet = RecipeApprovalSheet(request: request)
    }

    var isReadOnly: Bool { !sheet.isDecision }

    func binding(trigger key: String) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.sheet.triggers.first { $0.id == key }?.isOn ?? false },
                set: { [weak self] on in self?.sheet.setTrigger(key, on: on) })
    }

    func binding(gate: RecipeGateType) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.sheet.gates.first { $0.gate == gate }?.isOn ?? false },
                set: { [weak self] on in self?.sheet.setGate(gate, on: on) })
    }

    /// Approve: asks first when a trigger stays off (upstream "Triggers Left Off", Go Back is the default).
    func approve() {
        Task { @MainActor in
            guard isArmed, let decision = sheet.approval(openInEditor: openInEditor) else { return }
            if let text = sheet.leftOffText, let confirm {
                let buttons = [String(localized: "Go Back"), String(localized: "Approve")]
                guard await confirm(String(localized: "Triggers Left Off"), text, buttons) == 1 else { return }
            }
            onFinish?(decision)
        }
    }

    /// Reject / Block; in a review "Revoke Approval", after asking (Keep is the default).
    func reject() {
        guard sheet.isReview else {
            onFinish?(nil)
            return
        }
        Task { @MainActor in
            if let confirm {
                let buttons = [String(localized: "Keep"), String(localized: "Revoke")]
                guard await confirm(String(localized: "Revoke Approval"), sheet.revokeText, buttons) == 1 else { return }
            }
            onFinish?(.revoked)
        }
    }

    /// Keep as Is (a review), Close (validation error, Details).
    func close() {
        onFinish?(nil)
    }

    func showInFinder() {
        guard let url = sheet.request.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Upstream "Edit Recipe File": the file in the app for JSON files; TextEdit when that is Greenshot or there is none.
    func editFile() {
        guard let url = sheet.request.fileURL else { return }
        let own = Bundle.main.bundleIdentifier
        if let app = NSWorkspace.shared.urlForApplication(toOpen: url), Bundle(url: app)?.bundleIdentifier != own {
            NSWorkspace.shared.open(url)
            return
        }
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { log.warn("Could not open the recipe file in TextEdit", error: error) }
        }
    }

    func copyJSON() {
        Clipboard.copy(text: sheet.request.content)
    }
}
