// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

@Suite("TerminalSafeText")
struct TerminalSafeTextTests {
    @Test func osc52ClipboardWriteIsMadeVisible() {
        let qr = "\u{1B}]52;c;aGFja2Vk\u{07}"
        let shown = TerminalSafeText.sanitize(qr)
        #expect(shown == "\\x1b]52;c;aGFja2Vk\\x07")
        #expect(!shown.unicodeScalars.contains("\u{1B}"))
    }

    @Test func lineEraseAndCarriageReturnAreMadeVisible() {
        #expect(TerminalSafeText.sanitize("\u{1B}[2K\rfine") == "\\x1b[2K\\x0dfine")
    }

    @Test func newlineTabAndTextStay() {
        #expect(TerminalSafeText.sanitize("a\tb\nc ü 日本") == "a\tb\nc ü 日本")
    }

    @Test func delAndC1ControlsAreMadeVisible() {
        #expect(TerminalSafeText.sanitize("\u{7F}\u{9B}31m\u{85}") == "\\x7f\\x9b31m\\x85")
    }

    @Test func dataOfCleanTextIsUnchanged() {
        let data = Data("plain text\n".utf8)
        #expect(TerminalSafeText.sanitize(data) == data)
        #expect(TerminalSafeText.sanitize(Data()) == Data())
    }

    @Test func dataWithAnEscapeIsSanitised() {
        let data = Data([0x68, 0x1B, 0x5D, 0x38])
        #expect(String(decoding: TerminalSafeText.sanitize(data), as: UTF8.self) == "h\\x1b]8")
    }
}
