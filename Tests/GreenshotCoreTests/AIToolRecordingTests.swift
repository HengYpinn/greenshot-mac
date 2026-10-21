// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The RecordVideo step started by an AI tool follows the Source step's rule (security review SM-L1): the window of an
/// app excluded from AI tools isn't recorded, and a display or region recording leaves those apps out.
@Suite struct AIToolRecordingTests {
    let list = AIToolsSettings.defaultExcludedApplications
    let region = VideoCaptureTarget.region(CGRect(x: 0, y: 0, width: 800, height: 600))

    func rule(_ trigger: String?, _ target: VideoCaptureTarget, window: (app: String, names: [String?])? = nil,
              excluded: [String]? = nil) -> RecipeRecordVideoPlan.AIToolRule {
        RecipeRecordVideoPlan.aiToolRule(triggerType: trigger, target: target, window: window, excluded: excluded ?? list)
    }

    @Test func otherRunsRecordAsBefore() {
        let vault: (app: String, names: [String?]) = ("1Password", ["com.1password.1password"])
        #expect(rule(nil, .window(7), window: vault) == .unrestricted)
        #expect(rule(WellKnownTriggerType.hotkey, .window(7), window: vault) == .unrestricted)
        #expect(rule(WellKnownTriggerType.commandline, .display(1)) == .unrestricted)
        #expect(rule(WellKnownTriggerType.hotkey, region) == .unrestricted)
    }

    /// Like the Source step's window: refused, also when only a helper's bundle identifier is on the list.
    @Test func aWindowOfAnExcludedAppIsRefused() {
        let byName = rule(WellKnownTriggerType.aiTool, .window(7), window: (app: "1Password 7", names: [nil]))
        #expect(byName == .refused("Windows of '1Password 7' are excluded from AI tools (Settings › AI Tools)."))
        let byBundle = rule(WellKnownTriggerType.aiTool, .window(7), window: (app: "Agent", names: ["com.agilebits.onepassword7-helper"]))
        #expect(byBundle == .refused("Windows of 'Agent' are excluded from AI tools (Settings › AI Tools)."))
        // The trigger type in any case, like the other AI tool checks
        let lowercase = rule("aitool", .window(7), window: (app: "Bitwarden", names: []))
        #expect(lowercase != .unrestricted)
    }

    @Test func aWindowOfAnotherAppIsRecorded() {
        let safari: (app: String, names: [String?]) = ("Safari", ["com.apple.Safari", "Safari"])
        #expect(rule(WellKnownTriggerType.aiTool, .window(7), window: safari) == .unrestricted)
    }

    /// Fail closed: a window that can't be named isn't recorded for an AI tool.
    @Test func aWindowWithoutNamesIsRefused() {
        let refused = rule(WellKnownTriggerType.aiTool, .window(7), window: nil)
        #expect(refused != .unrestricted)
        #expect(refused != .leavingOut(list))
    }

    /// A display or a region: recorded without the excluded apps (the list as it is, matched by the recorder).
    @Test func aDisplayOrARegionLeavesTheExcludedAppsOut() {
        #expect(rule(WellKnownTriggerType.aiTool, .display(1)) == .leavingOut(list))
        #expect(rule(WellKnownTriggerType.aiTool, region) == .leavingOut(list))
        let own = rule(WellKnownTriggerType.aiTool, region, excluded: ["MyVault", " ", ""])
        #expect(own == .leavingOut(["MyVault"]))
    }

    @Test func nothingExcludedRecordsAsBefore() {
        #expect(rule(WellKnownTriggerType.aiTool, .display(1), excluded: []) == .unrestricted)
        #expect(rule(WellKnownTriggerType.aiTool, region, excluded: ["  "]) == .unrestricted)
        let vault: (app: String, names: [String?]) = ("1Password", [])
        #expect(rule(WellKnownTriggerType.aiTool, .window(7), window: vault, excluded: []) == .unrestricted)
    }

    /// The apps a display or region recording shows: every app whose names aren't excluded, in their order.
    @Test func shownAppsLeaveOutEveryNameOfAnExcludedApp() {
        let apps: [(id: Int32, names: [String?])] = [
            (1, ["Safari", "com.apple.Safari"]),
            (2, ["1Password", "com.1password.1password"]),
            (3, ["Agent", "com.agilebits.onepassword7-helper"]),
            (4, ["Finder", "com.apple.finder"]),
            (5, ["Bitwarden Helper (Renderer)", nil]),
        ]
        let shown = AIToolExclusion.shown(apps, names: \.names, excluded: list).map(\.id)
        #expect(shown == [1, 4])
        #expect(AIToolExclusion.shown(apps, names: \.names, excluded: []).count == apps.count)
    }

    /// The Source step's guard and the recording refuse with the same words.
    @Test func refusalNamesTheApp() {
        #expect(AIToolExclusion.refusal(appName: "Safari", names: ["com.apple.Safari"], excluded: list) == nil)
        let refusal = AIToolExclusion.refusal(appName: "KeePassXC", names: [], excluded: list)
        #expect(refusal == "Windows of 'KeePassXC' are excluded from AI tools (Settings › AI Tools).")
    }

    /// The step's own options show everything; only an AI tool's run sets the list.
    @Test func optionsShowEverythingByDefault() {
        let options = VideoCaptureOptions(target: .display(1), outputURL: URL(fileURLWithPath: "/tmp/recipe-video.mp4"))
        #expect(options.excludedApplications.isEmpty)
    }
}
