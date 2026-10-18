// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import GreenshotCore

/// A destination step's print options (upstream `DestinationExportStep.cs:167-191`): over the settings, for one print.
@Suite struct RecipePrintOptionsTests {
    func step(_ parameters: JSONObject = [:]) -> RecipeStepInvocation {
        RecipeStepInvocation(node: RecipeNode(id: "print", stepType: WellKnownStepType.destinations, parameters: parameters),
                             parameters: parameters, contract: StepContractCatalog.builtIn.contract(for: WellKnownStepType.destinations))
    }

    @Test func nothingSetIsNoOptions() {
        #expect(RecipePrintOptions.apply(step(), to: PrintSettings()) == nil)
        // Other parameters of the step aren't print options.
        #expect(RecipePrintOptions.apply(step(["PrinterName": .string("Office")]), to: PrintSettings()) == nil)
    }

    @Test func eachFlag() throws {
        var base = PrintSettings()
        base.promptOptions = true
        base.allowRotate = false
        base.allowEnlarge = false
        base.allowShrink = true
        base.center = true
        base.footer = true
        let options = try #require(RecipePrintOptions.apply(step(["ShowPrintDialog": .bool(false), "AllowRotate": .bool(true),
                                                                   "AllowEnlarge": .bool(true), "AllowShrink": .bool(false),
                                                                   "Center": .bool(false), "PrintFooter": .bool(false)]), to: base))
        #expect(!options.promptOptions)
        #expect(options.allowRotate)
        #expect(options.allowEnlarge)
        #expect(!options.allowShrink)
        #expect(!options.center)
        #expect(!options.footer)
    }

    /// One value set: the rest stays the settings'.
    @Test func unsetValuesComeFromTheSettings() throws {
        var base = PrintSettings()
        base.inverted = true
        base.allowEnlarge = true
        base.footerPattern = "${title}"
        let options = try #require(RecipePrintOptions.apply(step(["AllowRotate": .bool(true)]), to: base))
        #expect(options.allowRotate)
        #expect(options.inverted)
        #expect(options.allowEnlarge)
        #expect(options.footerPattern == "${title}")
        #expect(options.promptOptions == base.promptOptions)
    }

    @Test func colorModes() throws {
        var base = PrintSettings()
        base.grayscale = true
        let color = try #require(RecipePrintOptions.apply(step(["ColorMode": .string("Color")]), to: base))
        #expect(!color.grayscale)
        #expect(!color.monochrome)
        let gray = try #require(RecipePrintOptions.apply(step(["ColorMode": .string("Grayscale")]), to: PrintSettings()))
        #expect(gray.grayscale)
        #expect(!gray.monochrome)
        let mono = try #require(RecipePrintOptions.apply(step(["ColorMode": .string("monochrome")]), to: base))
        #expect(mono.monochrome)
        #expect(!mono.grayscale)
    }

    /// An administrator's locked print options win over the recipe's (wave 4's settings copy re-applied them too).
    @Test func lockedValuesWinOverTheRecipe() throws {
        let policy = ManagedPolicy(source: ManagedValues(forced: ["Greenshot.printing.grayscale": true,
                                                                  "Greenshot.printing.allowRotate": false]))
        let settings = policy.effective(AppSettings())
        let options = try #require(RecipePrintOptions.apply(step(["ColorMode": .string("Color"), "AllowRotate": .bool(true),
                                                                   "Center": .bool(false)]), to: settings.printing))
        // The recipe asked for colour and rotation; the policy keeps grayscale and no rotation.
        #expect(!options.grayscale)
        let printed = RecipePrintOptions.enforcingLocks(options, policy: policy, settings: settings)
        #expect(printed.grayscale)
        #expect(!printed.allowRotate)
        // What isn't locked stays the recipe's.
        #expect(!printed.center)
        #expect(!printed.monochrome)
    }

    /// The dialog of one print can't change a locked value either.
    @Test func lockedValuesWinOverTheDialog() {
        let policy = ManagedPolicy(source: ManagedValues(forced: ["Greenshot.printing": ["footer": false]]))
        let settings = policy.effective(AppSettings())
        var asked = settings.printing
        asked.footer = true
        asked.inverted = true
        let printed = RecipePrintOptions.enforcingLocks(asked, policy: policy, settings: settings)
        #expect(!printed.footer)
        #expect(printed.inverted)
    }

    @Test func nothingLockedKeepsTheOptions() throws {
        let lockedElsewhere = ManagedPolicy(source: ManagedValues(forced: ["Greenshot.outputFormat": "jpg"]))
        #expect(lockedElsewhere.isLocked("outputFormat"))
        let options = try #require(RecipePrintOptions.apply(step(["ColorMode": .string("Monochrome")]), to: PrintSettings()))
        let printed = RecipePrintOptions.enforcingLocks(options, policy: lockedElsewhere, settings: AppSettings())
        #expect(printed == options)
        let none = RecipePrintOptions.enforcingLocks(options, policy: ManagedPolicy(), settings: AppSettings())
        #expect(none == options)
    }

    @Test func footerPattern() throws {
        let options = try #require(RecipePrintOptions.apply(step(["FooterPattern": .string("${capturetime} ${title}")]),
                                                            to: PrintSettings()))
        #expect(options.footerPattern == "${capturetime} ${title}")
    }
}
