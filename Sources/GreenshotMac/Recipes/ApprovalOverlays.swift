// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The approval window's viewers over its content (upstream's in-dialog JSON viewer, RCP-197/198): the recipe file as
/// read (the bytes that are hashed and approved) and the changes against the version before, "-" before and "+" after.
struct RecipeApprovalOverlayView: View {
    @ObservedObject var model: RecipeApprovalModel
    let overlay: RecipeApprovalModel.Overlay

    /// Upstream doesn't show files above 1 MB.
    static let maxShownLength = 1024 * 1024

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(overlay == .json ? "\(model.sheet.titleNoun) JSON" : "Changes (− before, + after)").font(.title3.bold())
                Text("— " + model.sheet.recipeName).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if overlay == .changes {
                    Picker("", selection: $model.changedLinesOnly) {
                        Text("Changed Lines").tag(true)
                        Text("All Lines").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            Group {
                if overlay == .json {
                    MonospacedTextView(text: jsonText)
                } else {
                    DiffLinesView(lines: diffLines)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            HStack {
                Text(model.sheet.fileText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if overlay == .json { Button("Copy") { model.copyJSON() } }
                if model.sheet.request.fileURL != nil { Button("Show in Finder") { model.showInFinder() } }
                Button("Close") { model.overlay = nil }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var jsonText: String {
        let content = model.sheet.request.content
        if content.isEmpty { return "// Recipe content unavailable." }
        if content.utf8.count > Self.maxShownLength { return "// Recipe file is too large to preview (> 1MB)." }
        return content
    }

    private var diffLines: [DiffLinesView.Line] {
        let request = model.sheet.request
        if model.changedLinesOnly {
            let text = RecipeTextDiff.unifiedText(request.previousContent, request.content)
            return text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }.map { line in
                switch line.first {
                case "+": return DiffLinesView.Line(text: String(line), kind: .added)
                case "-": return DiffLinesView.Line(text: String(line), kind: .removed)
                case "@": return DiffLinesView.Line(text: "⋯", kind: .gap)
                default: return DiffLinesView.Line(text: String(line), kind: .unchanged)
                }
            }
        }
        guard let diff = request.diff else {
            return [DiffLinesView.Line(text: "// The recipes are too large to compare (more than \(RecipeTextDiff.maxLines) lines).", kind: .gap)]
        }
        return diff.map { line in
            switch line.kind {
            case .added: return DiffLinesView.Line(text: "+ " + line.text, kind: .added)
            case .removed: return DiffLinesView.Line(text: "- " + line.text, kind: .removed)
            case .unchanged: return DiffLinesView.Line(text: "  " + line.text, kind: .unchanged)
            }
        }
    }
}

/// Lines of a diff, removed ones red and added ones green.
struct DiffLinesView: View {
    struct Line {
        enum Kind { case added, removed, unchanged, gap }
        var text: String
        var kind: Kind
    }

    let lines: [Line]

    var body: some View {
        // Long lines wrap: a recipe file reads by its keys, and nothing hides at the right edge.
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(line.kind == .gap ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .background(background(line.kind))
                }
            }
            .textSelection(.enabled)
            .padding(.vertical, 4)
        }
    }

    private func background(_ kind: Line.Kind) -> Color {
        switch kind {
        case .added: return Color.green.opacity(0.18)
        case .removed: return Color.red.opacity(0.18)
        case .unchanged, .gap: return Color.clear
        }
    }
}

/// Read-only monospaced text that can be selected and copied (an AppKit text view: fast for big files).
struct MonospacedTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        // No wrapping: JSON reads by its indentation.
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }
}
