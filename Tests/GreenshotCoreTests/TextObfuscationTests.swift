// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct TextObfuscationTests {
    /// Two recognized lines: "Password: Secret123" and "user@example.com".
    let lines = [
        RecognizedLine(text: "Password: Secret123", bounds: CGRect(x: 10, y: 10, width: 200, height: 20), words: [
            RecognizedWord(text: "Password:", bounds: CGRect(x: 10, y: 10, width: 90, height: 20)),
            RecognizedWord(text: "Secret123", bounds: CGRect(x: 110, y: 10, width: 100, height: 20)),
        ]),
        RecognizedLine(text: "user@example.com", bounds: CGRect(x: 10, y: 40, width: 160, height: 20), words: [
            RecognizedWord(text: "user@example.com", bounds: CGRect(x: 10, y: 40, width: 160, height: 20)),
        ]),
    ]

    func options(_ pattern: String, regex: Bool = false, caseSensitive: Bool = false,
                 scope: TextObfuscationSettings.Scope = .words) -> TextObfuscationSettings {
        var settings = TextObfuscationSettings()
        settings.searchPattern = pattern
        settings.useRegex = regex
        settings.caseSensitive = caseSensitive
        settings.scope = scope
        settings.paddingHorizontal = 0
        settings.paddingVertical = 0
        return settings
    }

    @Test func plainTextIgnoresCaseByDefault() throws {
        #expect(try TextObfuscation.matches(in: lines, settings: options("secret")) == [CGRect(x: 110, y: 10, width: 100, height: 20)])
        #expect(try TextObfuscation.matches(in: lines, settings: options("secret", caseSensitive: true)).isEmpty)
        #expect(try TextObfuscation.matches(in: lines, settings: options("Secret", caseSensitive: true)).count == 1)
    }

    @Test func anEmptyPatternMatchesAllText() throws {
        #expect(try TextObfuscation.matches(in: lines, settings: options("")).count == 3)
        #expect(try TextObfuscation.matches(in: lines, settings: options("", scope: .lines)).count == 2)
    }

    @Test func linesMatchOnTheWholeLine() throws {
        let found = try TextObfuscation.matches(in: lines, settings: options("password: secret", scope: .lines))
        #expect(found == [CGRect(x: 10, y: 10, width: 200, height: 20)])
        #expect(try TextObfuscation.matches(in: lines, settings: options("password: secret")).isEmpty)
    }

    @Test func regularExpressions() throws {
        let email = options("[a-z]+@[a-z]+\\.com", regex: true)
        #expect(try TextObfuscation.matches(in: lines, settings: email) == [CGRect(x: 10, y: 40, width: 160, height: 20)])
        #expect(try TextObfuscation.matches(in: lines, settings: options("\\d{3}$", regex: true)).count == 1)
        #expect(try TextObfuscation.matches(in: lines, settings: options("^PASS", regex: true)).count == 1)
        #expect(try TextObfuscation.matches(in: lines, settings: options("^PASS", regex: true, caseSensitive: true)).isEmpty)
        // Without the regex option the pattern is plain text.
        #expect(try TextObfuscation.matches(in: lines, settings: options("\\d{3}$")).isEmpty)
    }

    @Test func anInvalidRegularExpressionIsAnError() {
        #expect(throws: TextObfuscation.SearchError.invalidPattern("([a-z")) {
            try TextObfuscation.matches(in: lines, settings: options("([a-z", regex: true))
        }
    }

    @Test func paddingAndOffsetLikeUpstream() {
        var settings = TextObfuscationSettings()
        settings.paddingHorizontal = 10
        settings.paddingVertical = 20
        settings.offsetX = 3
        settings.offsetY = -2
        let box = TextObfuscation.padded(CGRect(x: 100, y: 50, width: 95, height: 20), settings: settings)
        // 95 * 10 % / 2 = 4.75, cut to 4; 20 * 20 % / 2 = 2.
        #expect(box == CGRect(x: 99, y: 46, width: 103, height: 24))
    }

    @Test func boxesStayInTheImage() throws {
        var settings = options("user")
        settings.offsetX = -20
        let found = try TextObfuscation.matches(in: lines, settings: settings, within: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(found == [CGRect(x: 0, y: 40, width: 100, height: 20)])
    }

    @Test func elementsForEachEffect() {
        let box = CGRect(x: 1, y: 2, width: 30, height: 10)
        let pixelate = TextObfuscation.annotations(for: [box], effect: .pixelate)
        #expect(pixelate.count == 1 && pixelate[0].kind == .obfuscate && pixelate[0].style.obfuscateMode == .pixelate)
        #expect(pixelate[0].bounds == box)
        #expect(TextObfuscation.annotations(for: [box], effect: .blur)[0].style.obfuscateMode == .blur)
        let highlight = TextObfuscation.annotations(for: [box, box], effect: .highlight)
        #expect(highlight.count == 2 && highlight[0].kind == .highlight && highlight[0].style.highlightMode == .text)
        #expect(TextObfuscation.annotations(for: [box], effect: .magnify)[0].style.highlightMode == .magnify)
        // The last used style of the kind is kept.
        let big = TextObfuscation.annotations(for: [box], effect: .pixelate) { _ in AnnotationStyle(pixelSize: 12) }
        #expect(big[0].style.pixelSize == 12)
    }
}
