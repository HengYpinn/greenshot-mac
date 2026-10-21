// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GreenshotCore

struct CaptureKeysTests {
    @Test func aLatinLetterIsTheLetterTyped() {
        // French AZERTY: the key at the US W types z, and that is the Z of the zoomer.
        #expect(CaptureKeys.letter(typed: "z", latin: { "w" }) == "z")
        #expect(CaptureKeys.letter(typed: "M", latin: { nil }) == "m")
        #expect(CaptureKeys.letter(typed: "[", latin: { "ü" }) == "[")
    }

    @Test func anotherScriptUsesTheLatinLayout() {
        // Russian, Greek, Hebrew: the key that types я, ζ or ז is the Z of the Latin layout macOS uses for shortcuts.
        #expect(CaptureKeys.letter(typed: "я", latin: { "z" }) == "z")
        #expect(CaptureKeys.letter(typed: "ζ", latin: { "Z" }) == "z")
        #expect(CaptureKeys.letter(typed: "ז", latin: { "z" }) == "z")
        #expect(CaptureKeys.letter(typed: nil, latin: { "m" }) == "m")
        // Neither knows a letter: nothing happens.
        #expect(CaptureKeys.letter(typed: "я", latin: { nil }) == "я")
    }
}
