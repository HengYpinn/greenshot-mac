// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The question the first time a program uses Greenshot through greenshot-mcp (upstream `AiToolAccess.ShowConsentPromptAsync`).
/// The user is probably typing in the AI tool, and a keystroke meant for it must not answer the question: it stays on
/// top without taking the keyboard (a non-activating panel that never becomes key), has no default button, ignores
/// Escape and Return, and its buttons react only a second after it was last shown unchanged (`ConsentArming`). "Allow"
/// counts only when no other program's window lies over it, and it opens at a slightly random place (security review
/// SM-M2). Closing it counts as "Don't Allow". The program's texts are shown cleaned (SM-L4).
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
            // Not always at the same place: harder to prepare a window over it
            var origin = panel.frame.origin
            origin.x += CGFloat.random(in: -60...60)
            origin.y += CGFloat.random(in: -40...40)
            panel.setFrameOrigin(origin)
            panel.orderFrontRegardless()
            (panel as? ConsentPanel)?.startArming()
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
        panel.title = String(localized: "AI Tool Access")
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

        let name = AIToolText.displayed(client.displayName, limit: 80)
        let title = NSTextField(wrappingLabelWithString: String(localized: "\(name) wants to use \(AppInfo.name) to list your windows and take screenshots, and to run Greenshot recipes."))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        // Each part on its own line, cut in the middle: a long or tricky path can't push the rest out of sight
        var details = [line(String(localized: "Program: \(BidiText.isolatedLTR(client.path))"))]
        if let script = client.identity.script { details.append(line(String(localized: "Script: \(BidiText.isolatedLTR(script))"))) }
        for note in client.identity.notes { details.append(line(note)) }
        details.append(line(client.signerText))
        var paragraphs = [String(localized: "Screenshots can contain anything that is visible on your screen. Windows of excluded applications (password managers by default) are never shared. You can change both in Settings › AI Tools.")]
        if client.identity.script != nil {
            paragraphs.append(String(localized: "\(name) runs scripts: only the script above is allowed, not every script \(name) runs."))
        }
        paragraphs.append(String(localized: "Allow \(name) to use \(AppInfo.name)?"))
        let body = NSTextField(wrappingLabelWithString: paragraphs.joined(separator: "\n\n"))
        for label in [title, body] { label.preferredMaxLayoutWidth = 380 }

        let deny = FirstClickButton(title: String(localized: "Don't Allow"), target: panel, action: #selector(ConsentPanel.deny))
        let allow = FirstClickButton(title: String(localized: "Allow"), target: panel, action: #selector(ConsentPanel.allow))
        for button in [deny, allow] {
            button.keyEquivalent = ""
            button.isEnabled = armed
        }
        panel.buttons = [deny, allow]
        let buttons = NSStackView(views: [NSView(), deny, allow])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let detailStack = NSStackView(views: details)
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 2
        let text = NSStackView(views: [title, detailStack, body, buttons])
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
            detailStack.widthAnchor.constraint(equalTo: text.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: text.widthAnchor),
        ])
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        return panel
    }

    /// One line of the program's details: cleaned, small, cut in the middle, the whole text as its tooltip.
    private static func line(_ text: String) -> NSTextField {
        let cleaned = AIToolText.displayed(text, limit: 1000)
        let label = NSTextField(labelWithString: cleaned)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.toolTip = cleaned
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

/// A panel that never takes the keyboard and doesn't close with Escape.
private final class ConsentPanel: NSPanel {
    var onAnswer: ((Bool?) -> Void)?
    var buttons: [NSButton] = []
    private var arming: ConsentArming?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        // Escape: not an answer
    }

    func startArming() {
        let arming = ConsentArming(window: self, buttons: buttons)
        self.arming = arming
        arming.start()
    }

    @objc func allow() {
        // Only an armed, uncovered question counts (SM-M2)
        if let arming, !arming.confirmAllow() { return }
        answer(true)
    }
    @objc func deny() { answer(false) }

    override func close() {
        answer(nil)
        super.close()
    }

    private func answer(_ value: Bool?) {
        guard let handler = onAnswer else { return }
        onAnswer = nil
        arming?.stop()
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
