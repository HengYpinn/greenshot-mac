// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore

/// The tools of the editor, with upstream's one-letter shortcuts.
enum EditorTool: CaseIterable {
    case select, rectangle, ellipse, line, arrow, freehand, text, speechBubble, highlight, obfuscate, counter, emoji, crop

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
        }
    }

    var title: String {
        switch self {
        case .select: return "Select"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .freehand: return "Freehand"
        case .text: return "Text"
        case .speechBubble: return "Speech Bubble"
        case .highlight: return "Highlight"
        case .obfuscate: return "Obfuscate"
        case .counter: return "Counter"
        case .emoji: return "Emoji"
        case .crop: return "Crop"
        }
    }

    /// The title in the Object menu (upstream's Object menu items).
    var menuTitle: String {
        switch self {
        case .select: return "Select"
        case .rectangle: return "Add Rectangle"
        case .ellipse: return "Add Ellipse"
        case .line: return "Draw Line"
        case .arrow: return "Draw Arrow"
        case .freehand: return "Draw Freehand"
        case .text: return "Add Text"
        case .speechBubble: return "Add Speech Bubble"
        case .counter: return "Add Counter"
        case .emoji: return "Add Emoji"
        case .highlight: return "Highlight"
        case .obfuscate: return "Obfuscate"
        case .crop: return "Crop"
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
