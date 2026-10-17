// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import SwiftUI

/// The UserPrompt step's window (upstream `RecipeUserPromptWindow`, "Greenshot - Decision Prompt"): the title, the
/// message, the capture's preview, a button per choice (Primary, Secondary, Danger), the countdown "Auto-selecting
/// default choice in Ns" that picks the default choice. Return picks the default choice, Esc the cancel choice, the
/// close button the cancel choice as well (and stops the countdown).
struct RecipePromptPresenter: RecipePromptPresenting {
    func ask(_ prompt: RecipePrompt, preview: CGImage?, in context: RecipeFlowContext) async throws -> RecipePrompt.Answer {
        let window = RecipePromptWindowHandle()
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<RecipePrompt.Answer, Never>) in
                Task { @MainActor in
                    window.controller = RecipePromptPanel.show(prompt, preview: preview) { continuation.resume(returning: $0) }
                }
            }
        } onCancel: {
            Task { @MainActor in window.controller?.close() }
        }
        try Task.checkCancellation()
        return answer
    }
}

/// The open prompt of a flow, so a cancelled flow can close it.
final class RecipePromptWindowHandle: @unchecked Sendable {
    @MainActor var controller: RecipePromptPanel?
}

/// What the prompt view shows and how many seconds are left.
@MainActor
final class RecipePromptModel: ObservableObject {
    let prompt: RecipePrompt
    let preview: NSImage?
    @Published var secondsLeft: Int
    var choose: (String) -> Void = { _ in }

    init(prompt: RecipePrompt, preview: CGImage?) {
        self.prompt = prompt
        self.preview = preview.map { NSImage(cgImage: $0, size: .zero) }
        secondsLeft = prompt.timeoutSeconds
    }
}

struct RecipePromptView: View {
    @ObservedObject var model: RecipePromptModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.prompt.title)
                .font(.title3.weight(.semibold))
            Text(model.prompt.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let preview = model.preview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            }
            let countdown = RecipePrompt.countdownText(model.secondsLeft)
            if !countdown.isEmpty {
                Text(countdown)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(model.prompt.choices, id: \.key) { choice in
                    button(choice)
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func button(_ choice: RecipePromptChoice) -> some View {
        let isDefault = recipeEqualsKey(choice.key, model.prompt.defaultKey)
        switch choice.style {
        case .primary:
            Button(choice.label) { model.choose(choice.key) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(isDefault ? .defaultAction : nil)
        case .danger:
            Button(choice.label, role: .destructive) { model.choose(choice.key) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(isDefault ? .defaultAction : nil)
        case .secondary:
            Button(choice.label) { model.choose(choice.key) }
                .buttonStyle(.bordered)
                .keyboardShortcut(isDefault ? .defaultAction : nil)
        }
    }

    private func recipeEqualsKey(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}

/// The prompt's panel and its countdown; `done` gets the answer once.
@MainActor
final class RecipePromptPanel: NSObject, NSWindowDelegate {
    private static var open: [RecipePromptPanel] = []

    private let panel: RecipeKeyPanel
    private let model: RecipePromptModel
    private var timer: Timer?
    /// The window is closing by its close button: it mustn't be closed again.
    private var closing = false
    private var done: ((RecipePrompt.Answer) -> Void)?

    static func show(_ prompt: RecipePrompt, preview: CGImage?, done: @escaping (RecipePrompt.Answer) -> Void) -> RecipePromptPanel {
        let controller = RecipePromptPanel(prompt: prompt, preview: preview, done: done)
        open.append(controller)
        controller.panel.center()
        NSApp.activate()
        controller.panel.makeKeyAndOrderFront(nil)
        controller.startCountdown()
        return controller
    }

    private init(prompt: RecipePrompt, preview: CGImage?, done: @escaping (RecipePrompt.Answer) -> Void) {
        model = RecipePromptModel(prompt: prompt, preview: preview)
        self.done = done
        let hosting = NSHostingView(rootView: RecipePromptView(model: model))
        hosting.layoutSubtreeIfNeeded()
        panel = RecipeKeyPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize), styleMask: [.titled, .closable],
                               backing: .buffered, defer: false)
        super.init()
        panel.title = "Greenshot - \(prompt.title)"
        panel.contentView = hosting
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onReturn = { [weak self] in self?.finish(.enter) }
        panel.onEscape = { [weak self] in self?.finish(.escape) }
        model.choose = { [weak self] key in self?.finish(.chosen(key)) }
    }

    private func startCountdown() {
        guard model.secondsLeft > 0 else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.secondsLeft -= 1
                if self.model.secondsLeft <= 0 { self.finish(.timedOut) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Closes the window (a cancelled flow): the cancel choice, like the close button.
    func close() {
        finish(.closed)
    }

    private func finish(_ answer: RecipePrompt.Answer) {
        timer?.invalidate()
        timer = nil
        guard let done else { return }
        self.done = nil
        done(answer)
        panel.delegate = nil
        if !closing { panel.close() }
        Self.open.removeAll { $0 === self }
    }

    func windowWillClose(_ notification: Notification) {
        closing = true
        finish(.closed)
    }
}

/// A panel whose Return and Esc reach the prompt or the flyout (upstream's `KeyDown` handlers).
final class RecipeKeyPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let onReturn { onReturn() } else { super.keyDown(with: event) }
        case kVK_Escape:
            if let onEscape { onEscape() } else { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { super.cancelOperation(sender) }
    }
}
