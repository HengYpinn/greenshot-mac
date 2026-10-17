// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore

/// The tools of the editor, with upstream's one-letter shortcuts.
enum EditorTool: CaseIterable {
    case select, rectangle, ellipse, line, arrow, freehand, text, speechBubble, highlight, obfuscate, counter, emoji, cutMark, crop

    /// The element the tool draws.
    var kind: AnnotationKind? {
        switch self {
        case .select, .crop: return nil
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .arrow: return .arrow
        case .freehand: return .freehand
        case .text: return .text
        case .speechBubble: return .speechBubble
        case .highlight: return .highlight
        case .obfuscate: return .obfuscate
        case .counter: return .counter
        case .emoji: return .emoji
        case .cutMark: return .cutMark
        }
    }

    var title: String {
        switch self {
        case .select: return String(localized: "Select", comment: "The selection tool")
        case .rectangle: return String(localized: "Rectangle")
        case .ellipse: return String(localized: "Ellipse")
        case .line: return String(localized: "Line", comment: "The Line tool, draws a line")
        case .arrow: return String(localized: "Arrow")
        case .freehand: return String(localized: "Freehand")
        case .text: return String(localized: "Text", comment: "The Text tool, adds a text")
        case .speechBubble: return String(localized: "Speech Bubble")
        case .highlight: return String(localized: "Highlight")
        case .obfuscate: return String(localized: "Obfuscate")
        case .counter: return String(localized: "Counter")
        case .emoji: return String(localized: "Emoji")
        case .cutMark: return String(localized: "Cut Mark")
        case .crop: return String(localized: "Crop", comment: "The Crop tool")
        }
    }

    /// The title in the Object menu (upstream's Object menu items).
    var menuTitle: String {
        switch self {
        case .select: return String(localized: "Select", comment: "The selection tool")
        case .rectangle: return String(localized: "Add Rectangle")
        case .ellipse: return String(localized: "Add Ellipse")
        case .line: return String(localized: "Draw Line")
        case .arrow: return String(localized: "Draw Arrow")
        case .freehand: return String(localized: "Draw Freehand")
        case .text: return String(localized: "Add Text")
        case .speechBubble: return String(localized: "Add Speech Bubble")
        case .counter: return String(localized: "Add Counter")
        case .emoji: return String(localized: "Add Emoji")
        case .cutMark: return String(localized: "Add Cut Mark")
        case .highlight: return String(localized: "Highlight")
        case .obfuscate: return String(localized: "Obfuscate")
        case .crop: return String(localized: "Crop", comment: "The Crop tool")
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .freehand: return "scribble"
        case .text: return "textformat"
        case .speechBubble: return "bubble.left"
        case .highlight: return "highlighter"
        case .obfuscate: return "eye.slash"
        case .counter: return "1.circle"
        case .emoji: return "face.smiling"
        case .cutMark: return "scissors"
        case .crop: return "crop"
        }
    }

    var shortcut: Character {
        switch self {
        case .select: return "v"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .line: return "l"
        case .arrow: return "a"
        case .freehand: return "f"
        case .text: return "t"
        case .speechBubble: return "s"
        case .highlight: return "h"
        case .obfuscate: return "o"
        case .counter: return "i"
        case .emoji: return "m"
        // Upstream has no shortcut for cut marks (they come from its crop-out operation); K is free here.
        case .cutMark: return "k"
        case .crop: return "c"
        }
    }
}

/// The emoji to pick from. Upstream has a full emoji picker (`Greenshot.Editor/Controls/Emoji`); this is a short list
/// of ones that suit screenshots.
enum EmojiChoices {
    static let all = ["🙂", "😀", "😂", "😍", "😎", "🤔", "😮", "😢", "😡", "🙈", "👍", "👎", "👏", "🙏", "👉", "👀",
                      "❤️", "⭐️", "✅", "❌", "⚠️", "❓", "❗️", "💡", "🔥", "🎉", "🐛", "🚀"]
}
