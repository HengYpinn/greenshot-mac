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
        func elements(_ effect: TextObfuscationSettings.Effect, _ change: (inout TextObfuscationSettings) -> Void = { _ in }) -> [Annotation] {
            var settings = TextObfuscationSettings()
            settings.effect = effect
            change(&settings)
            return TextObfuscation.annotations(for: [box], settings: settings)
        }
        let pixelate = elements(.pixelate)
        #expect(pixelate.count == 1 && pixelate[0].kind == .obfuscate && pixelate[0].style.obfuscateMode == .pixelate)
        #expect(pixelate[0].bounds == box)
        #expect(elements(.blur)[0].style.obfuscateMode == .blur)
        let highlight = elements(.highlight)
        #expect(highlight.count == 1 && highlight[0].kind == .highlight && highlight[0].style.highlightMode == .text)
        #expect(elements(.magnify)[0].style.highlightMode == .magnify)
        #expect(TextObfuscation.annotations(for: [box, box], settings: TextObfuscationSettings()).count == 2)
    }

    @Test func theDialogsOptionsBecomeTheElementsStyle() {
        let box = CGRect(x: 1, y: 2, width: 30, height: 10)
        func style(_ effect: TextObfuscationSettings.Effect, _ change: (inout TextObfuscationSettings) -> Void) -> AnnotationStyle {
            var settings = TextObfuscationSettings()
            settings.effect = effect
            change(&settings)
            return TextObfuscation.annotations(for: [box], settings: settings)[0].style
        }
        // Upstream's slider defaults: 10 px, 10 px, 2×, yellow.
        #expect(style(.pixelate) { _ in }.pixelSize == 10)
        #expect(style(.blur) { _ in }.blurRadius == 10)
        #expect(style(.magnify) { _ in }.magnification == 2)
        #expect(style(.highlight) { _ in }.fillColor == .yellow)
        #expect(style(.pixelate) { $0.pixelSize = 25 }.pixelSize == 25)
        #expect(style(.blur) { $0.blurRadius = 3 }.blurRadius == 3)
        #expect(style(.magnify) { $0.magnification = 4 }.magnification == 4)
        #expect(style(.highlight) { $0.highlightColor = .blue }.fillColor == .blue)
        // The other options of a kind stay at the defaults; nonsense values are kept usable.
        #expect(style(.pixelate) { $0.blurRadius = 3 }.blurRadius == AnnotationStyle.defaults(for: .obfuscate).blurRadius)
        #expect(style(.pixelate) { $0.pixelSize = 0 }.pixelSize == 1)
    }

    @Test func oldOptionsLoadWithTheDefaultEffectOptions() throws {
        let json = #"{"searchPattern":"secret","useRegex":true,"caseSensitive":false,"scope":"lines","effect":"blur","paddingHorizontal":5,"paddingVertical":5,"offsetX":1,"offsetY":-1}"#
        let settings = try JSONDecoder().decode(TextObfuscationSettings.self, from: Data(json.utf8))
        #expect(settings.searchPattern == "secret" && settings.useRegex && settings.scope == .lines && settings.effect == .blur)
        #expect(settings.pixelSize == 10 && settings.blurRadius == 10 && settings.magnification == 2 && settings.highlightColor == .yellow)
        var changed = settings
        changed.magnification = 5
        changed.highlightColor = .red
        let decoded = try JSONDecoder().decode(TextObfuscationSettings.self, from: JSONEncoder().encode(changed))
        #expect(decoded == changed)
    }
}
