// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Recipe texts the app shows translated although they are data (built-in names), and texts built from parts.
struct LocalizedRecipeTextsTests {
    private static func german(_ english: String) -> String {
        ["Capture region": "Bereich abfotografieren", "Captures a region": "Fotografiert einen Bereich ab"][english] ?? english
    }

    @Test func theManagerFindsBuiltInsByTheirShownName() {
        let items = [
            RecipeManagerItem(id: "region", name: "Capture region", description: "Captures a region", isBuiltIn: true),
            RecipeManagerItem(id: "mine", name: "Capture region", description: "A file of the user"),
            RecipeManagerItem(id: "changed", name: "Capture region", isBuiltIn: true, isOverridden: true),
        ]
        let byName = RecipeManagerList.filter(items, by: .all, query: "bereich", display: Self.german).map(\.id)
        #expect(byName == ["region"])
        let byDescription = RecipeManagerList.filter(items, by: .all, query: "Fotografiert", display: Self.german).map(\.id)
        #expect(byDescription == ["region"])
        let english = RecipeManagerList.filter(items, by: .all, query: "Capture region", display: Self.german).map(\.id)
        #expect(english == ["region", "mine", "changed"])
    }

    @Test func aQuickSettingKeepsItsPartsApart() {
        let option = RecipeOption(key: "Enabled", type: .boolean)
        let plain = RecipeQuickSetting(ownerId: "ext_border", option: option, label: "Add a border", value: .bool(true))
        #expect(plain.optionLabel == "Add a border")
        #expect(plain.ownerName == nil)
        let named = RecipeQuickSetting(ownerId: "window", option: option, label: "Capture window: Add a border", value: .bool(true),
                                       optionLabel: "Add a border", ownerName: "Capture window")
        #expect(named.optionLabel == "Add a border")
        #expect(named.ownerName == "Capture window")
    }

    @Test func scriptMessagesStayEnglishInTests() {
        let failure = AppleScriptFailure(number: nil, message: "")
        #expect(failure.errorDescription == "The script failed.")
    }
}
