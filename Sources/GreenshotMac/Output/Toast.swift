// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// A short message after something happened: a macOS notification when the app can post them, else the in-app panel
/// (`ToastPanel`). Callers filter by the message level first (`ImageSaver.notify`).
@MainActor
enum Toast {
    static func show(_ message: String, detail: String? = nil, kind: MessageKind = .info, action: (() -> Void)? = nil,
                     onClosed: (() -> Void)? = nil) {
        NotificationService.shared.message(message, detail: detail, kind: kind, action: action, onClosed: onClosed)
    }

    /// Hides the in-app panel, e.g. before a capture (a macOS notification stays in Notification Center).
    static func dismiss() {
        ToastPanel.dismiss()
    }
}

/// The in-app message in the top right corner, where macOS notifications are not available (a build without an app
/// bundle, or macOS refused them): port of upstream's tray balloon (`TrayIcon.ShowBalloon` / `HideBalloon`): a title,
/// lines, the icon of its kind, a click action, and a closed callback that runs however it goes (clicked, timed out,
/// replaced or hidden).
@MainActor
enum ToastPanel {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?
    private static var onClosed: (() -> Void)?

    static func show(title: String, lines: [String] = [], kind: MessageKind = .info, action: (() -> Void)? = nil,
                     onClosed: (() -> Void)? = nil) {
        // A new message replaces the one shown (upstream `ShowBalloon`).
        dismiss()
        let content = makeView(title: title, lines: lines, kind: kind) {
            action?()
            dismiss()
        }
        let size = content.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            onClosed?()
            return
        }
        let frame = NSRect(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 16, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel
        self.onClosed = onClosed

        let work = DispatchWorkItem { dismiss(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration(lines: lines.count), execute: work)
    }

    /// 3.5 s, a second more for every further line, at most 8 s.
    static func duration(lines: Int) -> TimeInterval {
        min(8, 3.5 + Double(max(0, lines - 1)))
    }

    /// Hides the message (upstream `HideBalloon`); its closed callback runs.
    static func dismiss(animated: Bool = false) {
        hideWork?.cancel()
        hideWork = nil
        let closed = onClosed
        onClosed = nil
        if let panel {
            self.panel = nil
            if animated {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                                    completionHandler: { panel.orderOut(nil) })
            } else {
                panel.orderOut(nil)
            }
        }
        closed?()
    }

    /// The panel's content, also for the snapshots.
    static func makeView(title: String, lines: [String], kind: MessageKind, onClick: @escaping () -> Void = {}) -> NSView {
        ToastView(title: title, lines: lines, kind: kind, onClick: onClick)
    }

    /// The icon of a message's kind, like the balloon's info, warning and error icons.
    static func icon(for kind: MessageKind, pointSize: CGFloat = 20) -> NSImage? {
        let name: String
        let color: NSColor
        switch kind {
        case .info:
            name = "info.circle.fill"
            color = .systemBlue
        case .warning:
            name = "exclamationmark.triangle.fill"
            color = .systemYellow
        case .error:
            name = "xmark.octagon.fill"
            color = .systemRed
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white, color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: kindDescription(kind))?.withSymbolConfiguration(configuration)
    }

    private static func kindDescription(_ kind: MessageKind) -> String {
        switch kind {
        case .info: return String(localized: "Information")
        case .warning: return String(localized: "Warning")
        case .error: return String(localized: "Error")
        }
    }
}

private final class ToastView: NSVisualEffectView {
    private let onClick: () -> Void

    init(title: String, lines: [String], kind: MessageKind, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.lineBreakMode = .byTruncatingMiddle
        var texts: [NSView] = [heading]
        for line in lines {
            // A reason can be long: up to three lines.
            let label = NSTextField(wrappingLabelWithString: line)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 3
            label.cell?.truncatesLastVisibleLine = true
            label.preferredMaxLayoutWidth = 320
            texts.append(label)
        }
        let textStack = NSStackView(views: texts)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        var columns: [NSView] = []
        if let image = ToastPanel.icon(for: kind) {
            let icon = NSImageView(image: image)
            icon.setContentHuggingPriority(.required, for: .horizontal)
            columns.append(icon)
        }
        columns.append(textStack)
        let stack = NSStackView(views: columns)
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
