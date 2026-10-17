// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Text that must read left to right inside a right-to-left sentence (Arabic, Persian, Hebrew): a hotkey ("⌃⇧4"), a
/// path, a URL, a filename pattern. Without isolation the bidirectional algorithm can reorder its symbols.
public enum BidiText {
    /// LEFT-TO-RIGHT ISOLATE … POP DIRECTIONAL ISOLATE (Unicode TR #9) around `text`; harmless in left-to-right text.
    public static func isolatedLTR(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return String(Character(leftToRightIsolate)) + text + String(Character(popDirectionalIsolate))
    }

    /// U+2066.
    public static let leftToRightIsolate = Unicode.Scalar(0x2066)!
    /// U+2069.
    public static let popDirectionalIsolate = Unicode.Scalar(0x2069)!
}
