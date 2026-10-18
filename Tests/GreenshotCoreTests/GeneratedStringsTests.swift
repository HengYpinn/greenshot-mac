// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The committed tables of Resources/Localizations (scripts/l10n/l10n.py generate): they load, and every translation
/// keeps its key's placeholders, so no translation can break a format at run time.
struct GeneratedStringsTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let localizations = root.appendingPathComponent("Resources/Localizations", isDirectory: true)

    private static func table(_ lproj: String, _ name: String) throws -> [String: String] {
        let url = localizations.appendingPathComponent("\(lproj).lproj/\(name).strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String], "\(lproj)/\(name)")
    }

    /// [(position, conversion)] of a format's specifiers; nil for a `%` that is no specifier.
    static func specifiers(_ format: String) -> [String]? {
        let pattern = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(@|ll[duxX]|l[duxXf]|[dDiuUxXoOfFeEgGcCsSaAp])")
        var found: [(Int, String)] = []
        var sequential = 0
        let scalars = Array(format.utf16)
        var index = 0
        while index < scalars.count {
            guard scalars[index] == 37 else { index += 1; continue }  // %
            if index + 1 < scalars.count, scalars[index + 1] == 37 { index += 2; continue }
            let range = NSRange(location: index, length: scalars.count - index)
            guard let match = pattern.firstMatch(in: format, options: .anchored, range: range) else { return nil }
            let positionRange = match.range(at: 1)
            let position: Int
            if positionRange.location != NSNotFound {
                position = Int((format as NSString).substring(with: positionRange)) ?? 0
            } else {
                sequential += 1
                position = sequential
            }
            found.append((position, (format as NSString).substring(with: match.range(at: 2))))
            index = match.range.location + match.range.length
        }
        return found.sorted { $0.0 < $1.0 }.map { "\($0.0)\($0.1)" }
    }

    @Test func everyLanguageHasItsTables() throws {
        for pack in LanguagePacks.all {
            _ = try Self.table(pack.lproj, "Localizable")
            _ = try Self.table(pack.lproj, "Upstream")
        }
        let english = try Self.table("en", "Localizable")
        #expect(english.isEmpty)
    }

    /// The Mac's English of every key (`value` for an identifier key with a default value), from scripts/l10n/mac-keys.json.
    private static func englishTexts() throws -> [String: String] {
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/l10n/mac-keys.json"))
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: Any])
        let keys = try #require(json["keys"] as? [[String: Any]])
        var english: [String: String] = [:]
        for entry in keys {
            guard let key = entry["key"] as? String else { continue }
            english[key] = entry["value"] as? String ?? key
        }
        return english
    }

    /// A translation has the placeholders of the Mac's English (the default value for an identifier key), so it can't
    /// break a format at run time. A text without placeholders isn't formatted, by `String(localized:)` or SwiftUI (a
    /// table value "100 %" or "%d" shows as written), so its translation may contain a `%`, but no specifier.
    @Test func translationsKeepTheirPlaceholders() throws {
        let english = try Self.englishTexts()
        for pack in LanguagePacks.all {
            for (key, value) in try Self.table(pack.lproj, "Localizable") {
                let text = try #require(english[key], "\(pack.lproj): \(key) is no key of mac-keys.json")
                let expected = Self.specifiers(text) ?? []
                let found = Self.specifiers(value)
                if expected.isEmpty {
                    #expect(found?.isEmpty ?? true, "\(pack.lproj): \(key)")
                } else {
                    #expect(found == expected, "\(pack.lproj): \(key)")
                }
            }
        }
    }

    @Test func theSpecifierReader() {
        #expect(Self.specifiers("%2$@ of %1$lld") == ["1lld", "2@"])
        #expect(Self.specifiers("%lld%% done") == ["1lld"])
        #expect(Self.specifiers("50 % off") == nil)
    }
}
