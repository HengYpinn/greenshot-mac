// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The recipe commands of greenshot-cli and links (upstream `IpcSecurityDispatcher.HandleListRecipesAsync`,
/// `HandleDescribeRecipeAsync`, `HandleRunRecipeAsync`, `HandleRecipeEditorAsync`, `HandleRecipeManagerAsync`): the logic is
/// Core's `IPCRecipeCommands`; here the app's recipes and windows.
@MainActor
enum AutomationRecipes {
    static func register(in table: IPCCommandTable, app: AppDelegate) {
        table.register(IPCCommand.listRecipes) { [app] context in await listRecipes(app, context) }
        table.register(IPCCommand.describeRecipe) { [app] context in await describeRecipe(app, context) }
        table.register(IPCCommand.runRecipe) { [app] context in await runRecipe(app, context) }
        table.register(IPCCommand.recipeEditor) { context in
            await MainActor.run { RecipeEditorService.openEditor(recipeId: context.envelope.parameter("recipe")) }
            return .ok("Recipe Editor displayed.")
        }
        table.register(IPCCommand.recipeManager) { context in
            await MainActor.run { RecipeManagerService.show(selecting: context.envelope.parameter("recipe")) }
            return .ok("Recipe Manager displayed.")
        }
    }

    private static func loadedRecipes(_ app: AppDelegate) async -> RecipeRuntime {
        let recipes = app.recipes
        await recipes.whenLoaded()
        return recipes
    }

    private static func listRecipes(_ app: AppDelegate, _ context: IPCReplyContext) async -> IPCReply {
        let recipes = await loadedRecipes(app)
        return IPCRecipeCommands.listRecipes(context, library: recipes.library)
    }

    private static func describeRecipe(_ app: AppDelegate, _ context: IPCReplyContext) async -> IPCReply {
        let recipes = await loadedRecipes(app)
        return IPCRecipeCommands.describeRecipe(context, library: recipes.library)
    }

    /// RUN_RECIPE: a recipe of the command line that captures without the user asks first, like CAPTURE.
    private static func runRecipe(_ app: AppDelegate, _ context: IPCReplyContext) async -> IPCReply {
        let recipes = await loadedRecipes(app)
        return await IPCRecipeCommands.runRecipe(context, library: recipes.library, start: { recipes.start($0) },
                                                 confirmCapture: { name, subject in
                                                     AutomationCaptureConsent.ask(recipe: name, subject: subject, peer: context.peer)
                                                 })
    }
}
