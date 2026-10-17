// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The question the first time a program uses Greenshot through greenshot-mcp (upstream `AiToolAccess.ShowConsentPromptAsync`).
/// The user is probably typing in the AI tool, and a keystroke meant for it must not answer the question: it stays on
/// top without taking the keyboard (a non-activating panel that never becomes key), has no default button, ignores
/// Escape and Return, and its buttons react only after a second. Closing it counts as "Don't Allow".
@MainActor
enum AIToolsConsentPanel {
    static let armDelay: TimeInterval = 1
    private static let log = Log("AITools")

    /// The open questions (a panel isn't kept by being on the screen).
    private static var open: [NSPanel] = []

    /// True when the user clicked Allow.
    static func ask(_ client: AIToolClient) async -> Bool {
        await withCheckedContinuation { continuation in
            let panel = makePanel(client: client, armed: false) { allowed in
                let answer = allowed == true ? "clicked \"Allow\"" : allowed == false ? "clicked \"Don't Allow\"" : "closed the question without an answer"
                log.info("AI tool access for \(client.logText): the user \(answer).")
                continuation.resume(returning: allowed == true)
            }
            open.append(panel)
            panel.center()
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + armDelay) {
                MainActor.assumeIsolated { (panel as? ConsentPanel)?.arm() }
            }
        }
    }

    fileprivate static func closed(_ panel: NSPanel) {
        open.removeAll { $0 === panel }
    }

    /// The panel; `onAnswer` gets true (Allow), false (Don't Allow) or nil (closed). `armed`: buttons enabled at once
    /// (the snapshots).
    static func makePanel(client: AIToolClient, armed: Bool, onAnswer: @escaping (Bool?) -> Void) -> NSPanel {
        let panel = ConsentPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                                 styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "AI Tool Access"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onAnswer = onAnswer

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let title = NSTextField(wrappingLabelWithString: "\(client.displayName) wants to use \(AppInfo.name) to list your windows and take screenshots, and to run Greenshot recipes.")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let program = NSTextField(wrappingLabelWithString: "Program: \(client.path)\n\(client.signerText)")
        program.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        program.textColor = .secondaryLabelColor
        program.isSelectable = true
        let body = NSTextField(wrappingLabelWithString: "Screenshots can contain anything that is visible on your screen. Windows of excluded applications (password managers by default) are never shared. You can change both in Settings › AI Tools.\n\nAllow \(client.displayName) to use \(AppInfo.name)?")
        for label in [title, program, body] { label.preferredMaxLayoutWidth = 380 }

        let deny = FirstClickButton(title: "Don't Allow", target: panel, action: #selector(ConsentPanel.deny))
        let allow = FirstClickButton(title: "Allow", target: panel, action: #selector(ConsentPanel.allow))
        for button in [deny, allow] {
            button.keyEquivalent = ""
            button.isEnabled = armed
        }
        panel.buttons = [deny, allow]
        let buttons = NSStackView(views: [NSView(), deny, allow])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let text = NSStackView(views: [title, program, body, buttons])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        row.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor),
            row.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            text.widthAnchor.constraint(equalToConstant: 380),
            buttons.widthAnchor.constraint(equalTo: text.widthAnchor),
        ])
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        return panel
    }
}

/// A panel that never takes the keyboard and doesn't close with Escape.
private final class ConsentPanel: NSPanel {
    var onAnswer: ((Bool?) -> Void)?
    var buttons: [NSButton] = []

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        // Escape: not an answer
    }

    func arm() {
        buttons.forEach { $0.isEnabled = true }
    }

    @objc func allow() { answer(true) }
    @objc func deny() { answer(false) }

    override func close() {
        answer(nil)
        super.close()
    }

    private func answer(_ value: Bool?) {
        guard let handler = onAnswer else { return }
        onAnswer = nil
        orderOut(nil)
        handler(value)
        MainActor.assumeIsolated { AIToolsConsentPanel.closed(self) }
    }
}

/// A button that reacts to the first click in a panel that isn't key.
private final class FirstClickButton: NSButton {
    convenience init(title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
