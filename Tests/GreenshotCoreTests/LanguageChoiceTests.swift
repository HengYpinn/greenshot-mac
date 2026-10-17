// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The language at the start (`LanguageChoice`): profile, --language, setting, macOS.
struct LanguageChoiceTests {
    @Test func nothingChosenLeavesItToMacOS() {
        let choice = LanguageChoice.decide(commandLine: nil, setting: "", lockedByProfile: false, snapshot: false)
        #expect(choice.pack == nil)
        #expect(choice.source == .macOS)
        #expect(choice.saveToSettings == nil)
        #expect(choice.problems.isEmpty)
    }

    @Test func theSetting() {
        let choice = LanguageChoice.decide(commandLine: nil, setting: "de-DE", lockedByProfile: false, snapshot: false)
        #expect(choice.pack?.ietf == "de-DE")
        #expect(choice.source == .setting)
    }

    @Test func commandLineWinsAndIsKept() {
        let choice = LanguageChoice.decide(commandLine: "fr", setting: "de-DE", lockedByProfile: false, snapshot: false)
        #expect(choice.pack?.ietf == "fr-FR")
        #expect(choice.source == .commandLine)
        #expect(choice.saveToSettings == "fr-FR")
        let system = LanguageChoice.decide(commandLine: "system", setting: "de-DE", lockedByProfile: false, snapshot: false)
        #expect(system.pack == nil)
        #expect(system.saveToSettings == "")
    }

    @Test func unknownCodesAreIgnoredAndLogged() {
        let choice = LanguageChoice.decide(commandLine: "xx-YY", setting: "it-IT", lockedByProfile: false, snapshot: false)
        #expect(choice.pack?.ietf == "it-IT")
        #expect(choice.saveToSettings == nil)
        #expect(choice.problems.count == 1)
        let setting = LanguageChoice.decide(commandLine: nil, setting: "klingon", lockedByProfile: false, snapshot: false)
        #expect(setting.pack == nil)
        #expect(setting.source == .macOS)
        #expect(setting.problems.count == 1)
    }

    @Test func aProfileLocksTheLanguage() {
        let choice = LanguageChoice.decide(commandLine: "fr-FR", setting: "de-DE", lockedByProfile: true, snapshot: false)
        #expect(choice.pack?.ietf == "de-DE")
        #expect(choice.source == .managed)
        #expect(choice.saveToSettings == nil)
        #expect(choice.problems.count == 1)
        let empty = LanguageChoice.decide(commandLine: nil, setting: "", lockedByProfile: true, snapshot: false)
        #expect(empty.pack == nil)
        #expect(empty.source == .managed)
    }

    @Test func snapshotsAreEnglishUnlessAsked() {
        let english = LanguageChoice.decide(commandLine: nil, setting: "de-DE", lockedByProfile: true, snapshot: true)
        #expect(english.pack?.ietf == "en-US")
        #expect(english.source == .snapshot)
        let arabic = LanguageChoice.decide(commandLine: "ar-SY", setting: "", lockedByProfile: false, snapshot: true)
        #expect(arabic.pack?.ietf == "ar-SY")
        #expect(arabic.saveToSettings == nil)
    }

    @Test func argumentDomainValues() {
        let german = LanguagePacks.resolve("de-DE")
        let hebrew = LanguagePacks.resolve("he-IL")
        let chosen = LanguageChoice.argumentDomainValues(override: german, effective: german)
        #expect(chosen["AppleLanguages"] as? [String] == ["de"])
        #expect(chosen["AppleTextDirection"] == nil)
        let macOSHebrew = LanguageChoice.argumentDomainValues(override: nil, effective: hebrew)
        #expect(macOSHebrew["AppleLanguages"] == nil)
        #expect(macOSHebrew["AppleTextDirection"] as? Bool == true)
        #expect(macOSHebrew["NSForceRightToLeftWritingDirection"] == nil)
        #expect(LanguageChoice.argumentDomainValues(override: nil, effective: nil).isEmpty)
    }
}
