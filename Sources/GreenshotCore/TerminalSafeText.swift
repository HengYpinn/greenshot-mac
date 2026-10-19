// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Text from the screen on its way to a terminal (greenshot-cli on a TTY). A QR code, OCR text or a window title is
/// chosen by whoever made the page or the window, so it can carry escape sequences: OSC 52 writes the clipboard, OSC 8
/// makes a link that says something else, `ESC[2K` + CR hides what was printed before. On a terminal these are made
/// visible as `\xNN`; a pipe or a file gets the bytes exactly as they are.
public enum TerminalSafeText {
    /// `text` with ESC, the other C0 controls (but newline and tab), DEL and the C1 controls (U+0080 to U+009F) written
    /// as `\xNN`. Bytes that are not UTF-8 are shown as U+FFFD (a lone 0x9B is a CSI on some terminals).
    public static func sanitize(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let isControl = value < 0x20 || value == 0x7F || (0x80...0x9F).contains(value)
            if isControl, scalar != "\n", scalar != "\t" {
                result.append(contentsOf: String(format: "\\x%02x", value).unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    /// `sanitize` for a chunk of output; empty and clean chunks are returned as they are.
    public static func sanitize(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        let clean = sanitize(text)
        return clean.utf8.elementsEqual(data) ? data : Data(clean.utf8)
    }
}
