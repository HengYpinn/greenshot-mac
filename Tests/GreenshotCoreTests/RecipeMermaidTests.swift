// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// Upstream RecipeEditorViewModel.cs `GenerateMermaidDsl`.
@Suite struct RecipeMermaidTests {
    @Test func conditionalRecipeInUpstreamsFormat() {
        var recipe = EditorFixtures.conditional()
        recipe.nodes[0].name = "Capture \"Area\""
        recipe.triggers = [TriggerConfig(triggerType: "Hotkey", parameters: ["Hotkey": .string("Ctrl + Shift + B")])]
        recipe.flow.errorTransitions = [ErrorTransition(from: "large", to: "small")]
        let expected = """
        flowchart TD
            %% Triggers
            subgraph Triggers ["🚀 Triggers"]
                trigger_0(["⚡ Hotkey: Ctrl + Shift + B"])
            end

            %% Node Definitions
            source["Capture 'Area' (Source) [source]"]
            decide{"Conditional [decide]"}
            large["Editor [large]"]
            small["Clipboard [small]"]
            notify["Notification [notify]"]

            %% Trigger Invocations
            trigger_0 -.-> source

            %% Unconditional Transitions
            source --> decide
            large --> notify
            small --> notify

            %% Conditional Branch Transitions
            decide -- "A: ${payload.width > 800}" --> large
            decide -- "B: else" --> small

            %% Error Handling Fallbacks
            large -. "Error: *" .-> small

            %% Start Nodes Styling
            classDef startNode fill:#238636,stroke:#2ea043,stroke-width:2px,color:#ffffff;
            class source startNode;

            %% Triggers Styling
            classDef triggerNode fill:#d97706,stroke:#f59e0b,stroke-width:2px,color:#ffffff;
            class trigger_0 triggerNode;

        """
        #expect(RecipeMermaid.text(of: recipe) == expected)
    }

    @Test func emptyAndMinimal() {
        #expect(RecipeMermaid.text(of: nil) == "flowchart TD\n")
        let recipe = EditorFixtures.recipe(["a:Source"])
        #expect(RecipeMermaid.text(of: recipe) == """
        flowchart TD
            %% Node Definitions
            a["Source [a]"]

            %% Unconditional Transitions

            %% Start Nodes Styling
            classDef startNode fill:#238636,stroke:#2ea043,stroke-width:2px,color:#ffffff;
            class a startNode;

        """)
    }

    @Test func triggerLabels() {
        func label(_ type: String, _ parameters: JSONObject = [:], name: String? = nil, enabled: Bool = true) -> String {
            var trigger = TriggerConfig(triggerType: type, name: name, parameters: parameters)
            trigger.enabled = enabled
            return RecipeMermaid.triggerLabel(trigger)
        }
        #expect(label("Hotkey") == "⚡ Hotkey: Shortcut")
        #expect(label("ContextMenu", ["MenuItemText": .string("Grab")]) == "🖱️ Menu: Grab")
        #expect(label("Systray", name: "Tray") == "🖱️ Menu: Tray")
        #expect(label("Editor") == "🎨 Editor: Editor Menu")
        #expect(label("Clipboard") == "📋 Clipboard Monitor")
        #expect(label("Manual") == "⚡ Manual: User Action")
        #expect(label("Commandline", ["Command": .string("qr")]) == "💻 CLI: qr")
        #expect(label("OpenFile") == "📂 Open With File")
        #expect(label("Extension", ["Browser": .string("firefox")]) == "🌐 Browser Extension (firefox)")
        #expect(label("Extension") == "🌐 Browser Extension")
        #expect(label("AiTool", ["ToolName": .string("grab")]) == "🤖 AI tool: grab")
        #expect(label("Hotkey", ["Hotkey": .string("Ctrl + \"Q\"")], enabled: false) == "⚡ Hotkey: Ctrl + 'Q' (Disabled)")
        #expect(label("Strange", name: "Odd") == "⚡ Odd")
    }

    @Test func unsafeIdsAndAnyStep() {
        var recipe = EditorFixtures.recipe(["end:Source", "my step:Clipboard", "ok_1:Editor"], ["end>my step", "my step>ok_1"])
        recipe.flow.errorTransitions = [ErrorTransition(from: "*", targetRecipeId: "recipe.other")]
        let text = RecipeMermaid.text(of: recipe)
        #expect(text.contains("    n0[\"Source [end]\"]"))
        #expect(text.contains("    n1[\"Clipboard [my step]\"]"))
        #expect(text.contains("    n0 --> n1"))
        #expect(text.contains("    n1 --> ok_1"))
        #expect(text.contains("    any_step([\"Any step\"])"))
        #expect(text.contains("    any_step -. \"Error: *\" .-> Recipe_recipe_other"))
        #expect(text.contains("    class n0 startNode;"))
    }

    @Test func graphMarksStartsAndDecisions() {
        let graph = RecipeFlowGraph(EditorFixtures.conditional())
        #expect(graph.nodes.first { $0.id == "decide" }?.shape == .diamond)
        #expect(graph.nodes.first { $0.id == "source" }?.isStart == true)
        #expect(graph.edges.filter { $0.style == .conditional }.count == 2)
        let missing = RecipeFlowGraph(EditorFixtures.recipe(["a:Source"], ["a>ghost"]))
        #expect(missing.nodes.first { $0.role == .missing }?.label == "ghost (missing)")
        let ext = RecipeFlowGraph(RecipeEditorCatalog.newExtension())
        #expect(ext.nodes.contains { $0.role == .out })
    }
}
