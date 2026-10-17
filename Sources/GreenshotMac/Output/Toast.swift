// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// A short message in the top right corner (upstream shows a tray balloon). Needs no notification permission.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String, detail: String? = nil, kind: MessageKind = .info, action: (() -> Void)? = nil) {
        dismiss()
        let content = ToastView(message: message, detail: detail) {
            action?()
            dismiss()
        }
        let size = content.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
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

        let work = DispatchWorkItem { dismiss(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    static func dismiss(animated: Bool = false) {
        hideWork?.cancel()
        hideWork = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                            completionHandler: { panel.orderOut(nil) })
    }
}

private final class ToastView: NSVisualEffectView {
    private let onClick: () -> Void

    init(message: String, detail: String?, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        let title = NSTextField(labelWithString: message)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingMiddle
        var views: [NSView] = [title]
        if let detail {
            let subtitle = NSTextField(labelWithString: detail)
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = .secondaryLabelColor
            subtitle.lineBreakMode = .byTruncatingMiddle
            views.append(subtitle)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }
}
