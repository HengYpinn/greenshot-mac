// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Where the log text view scrolls after its text was replaced.
enum LogScrollTarget: Equatable {
    case end
    /// The UTF-16 offset of a line to show at the top (after "Load Earlier": where the text was before).
    case offset(Int)
}

/// The log as read-only, selectable monospaced text (upstream's `LogTextBox`). New text that only extends the shown
/// text is appended, and the view follows the end when it was scrolled to the end; other changes replace the text
/// (a new `generation`). ⌘F inside the text opens the find bar.
struct LogTextView: NSViewRepresentable {
    var text: String
    var generation: Int
    var scrollTarget: LogScrollTarget
    var wrap: Bool

    final class Coordinator {
        var generation = -1
        var length = 0
        var wrap: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.font = Self.font
            textView.textColor = .textColor
            textView.backgroundColor = .textBackgroundColor
            textView.textContainerInset = NSSize(width: 6, height: 6)
            textView.setAccessibilityLabel("Log")
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage else { return }
        let coordinator = context.coordinator
        if coordinator.wrap != wrap {
            coordinator.wrap = wrap
            Self.apply(wrap: wrap, to: textView, in: scrollView)
        }
        let length = text.utf16.count
        if coordinator.generation == generation, length > coordinator.length {
            let atEnd = Self.isScrolledToEnd(scrollView)
            let added = String(text.utf16.dropFirst(coordinator.length)) ?? ""
            storage.append(NSAttributedString(string: added, attributes: Self.attributes))
            coordinator.length = length
            if atEnd { Self.scrollToEnd(scrollView) }
        } else if coordinator.generation != generation || length != coordinator.length {
            coordinator.generation = generation
            coordinator.length = length
            storage.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
            switch scrollTarget {
            case .end:
                Self.scrollToEnd(scrollView)
            case .offset(let offset):
                textView.scrollRangeToVisible(NSRange(location: min(offset, length), length: 0))
            }
        }
    }

    static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]

    /// The last line at the bottom, the start of the lines on the left.
    private static func scrollToEnd(_ scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
        textView.sizeToFit()
        let visible = scrollView.contentView.bounds.height
        let y = max(0, textView.frame.height - visible)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func isScrolledToEnd(_ scrollView: NSScrollView) -> Bool {
        guard let document = scrollView.documentView else { return true }
        let visible = scrollView.contentView.documentVisibleRect
        return visible.maxY >= document.bounds.maxY - 2
    }

    private static func apply(wrap: Bool, to textView: NSTextView, in scrollView: NSScrollView) {
        let huge = CGFloat.greatestFiniteMagnitude
        scrollView.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        textView.autoresizingMask = wrap ? [.width] : []
        textView.maxSize = NSSize(width: huge, height: huge)
        textView.textContainer?.widthTracksTextView = wrap
        let width = wrap ? scrollView.contentSize.width : huge
        textView.textContainer?.containerSize = NSSize(width: width, height: huge)
        if wrap { textView.frame.size.width = scrollView.contentSize.width }
    }
}

/// A search field whose text is bound to the model and which the model can focus (⌘F).
struct LogSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCreate: (NSSearchField) -> Void

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.stringValue = text
        onCreate(field)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }
}
