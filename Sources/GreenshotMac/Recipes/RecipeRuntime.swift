// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by RSTEPS after the wave 4 prep. The declarations are the contract for RUI, REDITOR, RMANAGER, MCP and BROWSER:
// RSTEPS fills in the bodies without changing a signature.

import AppKit
import GreenshotCore

private let log = Log("Recipes")

/// A capture the app starts itself (hotkeys, menus, Open Image from File/Clipboard): upstream `CaptureHelper` starts the
/// built-in recipe for it. `RecipeRuntime.interceptBuiltIn` runs the recipe only when it differs from the stock one.
enum BuiltInCapture: Equatable {
    /// `recipe_region`
    case region
    /// `recipe_window`: the capture screen in window mode.
    case window
    /// `recipe_active_window`
    case activeWindow
    /// `recipe_active_window` with this window (upstream `CaptureWindow(IInteropWindow)`, object TargetWindow).
    case windowFromList(WindowInfo)
    /// `recipe_fullscreen`: every display (nil: the menu's "All Screens") or one display (object TargetDisplay).
    case fullScreen(display: CGDirectDisplayID?)
    /// `recipe_fullscreen` as the settings' ScreenCaptureMode says (the hotkey).
    case fullScreenFromHotkey
    /// `recipe_lastregion`
    case lastRegion
    /// `recipe_ocr`
    case text
    /// `recipe_clipboard`
    case clipboard
    /// `recipe_file` with the variable Filename.
    case file(URL)
}

/// How a trigger's start went (`RecipeRuntime.fire`).
enum RecipeFireOutcome {
    case started(RecipeFlowHandle)
    /// The trigger belongs to a stock built-in capture recipe: the caller does what the app does without recipes
    /// (the OpenFile trigger of `recipe_file`: open the file in the editor).
    case direct
    /// Not started: recipes are off, the trigger or the recipe is switched off, or the start was refused.
    case notStarted
}

/// MCP (AUT-071/072): an AI tool's window reference ("w7", a number) as the window to capture. Called on the step
/// executors' threads.
protocol RecipeWindowResolving: AnyObject, Sendable {
    func windowID(for reference: JSONValue) -> CGWindowID?
}

/// MCP (AUT-083): the apps AI tools never see (upstream `AiToolCapture`, `AiToolAccess.IsProcessExcluded`). Called on the
/// step executors' threads (black-filling a big picture doesn't belong on the main thread).
protocol RecipeAIToolCaptureGuard: AnyObject, Sendable {
    /// Settings › AI Tools' excluded applications (names, bundle identifier prefixes).
    var excludedApplications: [String] { get }
    /// Why this window may not be captured for an AI tool; nil when it may.
    func refusal(for window: WindowInfo) -> String?
    /// The picture with the windows of excluded apps blacked out; `origin` is its top left in Quartz global points.
    func redacted(_ image: CGImage, scale: CGFloat, origin: CGPoint) -> (image: CGImage, count: Int)
}

/// The editor a recipe works on: host object "EditorForm" of RUI's Editor trigger (Source CurrentEditor,
/// TargetEditor CurrentEditor).
@MainActor
final class RecipeEditorForm {
    weak var editor: EditorWindowController?

    init(editor: EditorWindowController) {
        self.editor = editor
    }
}

/// The approver the library holds from the start: forwards to RUI's approval sheet once `target` is set; until then
/// every request is refused (default-deny) and logged.
@MainActor
final class RecipeApproverProxy: RecipeApprover {
    var target: (any RecipeApprover)?

    func requestApproval(_ request: RecipeApprovalRequest) async -> RecipeApprovalDecision? {
        guard let target else {
            log.warn("No approval window yet: recipe file '\(request.fileURL?.lastPathComponent ?? "")' is not approved.")
            return nil
        }
        return await target.requestApproval(request)
    }

    func showValidationError(_ request: RecipeApprovalRequest) async {
        guard let target else {
            log.warn("Recipe file '\(request.fileURL?.lastPathComponent ?? "")' is not valid: \(request.errorMessage ?? "")")
            return
        }
        await target.showValidationError(request)
    }
}

/// The settings for the runner's environment, read off the main thread.
final class RecipeSettingsSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings

    init(_ settings: AppSettings) {
        self.settings = settings
    }

    var value: AppSettings {
        get { lock.withLock { settings } }
        set { lock.withLock { settings = newValue } }
    }
}

/// The recipes of the running app (upstream `RecipeManager` + `CaptureFlowRunner` + `TriggerManager` +
/// `CaptureHelper`): library, step executors, runner, trigger hub, trust store. One per app (`AppDelegate.recipes`).
/// Code that must also work without a started runtime (windows, `--snapshot`, the hooks in shared files) asks
/// `RecipeRuntime.shared`, which stays nil until `start()`.
@MainActor
final class RecipeRuntime {
    /// The app's runtime once `start()` ran; the hooks in CaptureCoordinator, EditorManager, MenuBarActions and
    /// NotificationService use it.
    private(set) static var shared: RecipeRuntime?

    let library: RecipeLibrary
    let runner: RecipeRunner
    let hub: RecipeTriggerHub
    let steps: RecipeStepRegistry
    let trustStore: RecipeTrustStore
    /// RUI sets `approver.target` to its approval sheet.
    let approver: RecipeApproverProxy
    /// Where new recipe files are saved by default (the recipe editor) and `AI/` for AI tools' proposals (upstream: the
    /// folder of greenshot.ini + "Recipes"). Created on demand by whoever writes into it.
    let recipesFolder: URL

    /// RMANAGER: the recipe with its switched-on automatic steps (upstream `GetEffectiveRecipe`); nil: recipes run as
    /// loaded. Returns its argument unchanged (==) when no automatic step applies.
    var composeForRun: (@MainActor (CaptureRecipe) -> CaptureRecipe)?
    /// RMANAGER: the BeforeDestination automatic steps of a (composed) recipe, for the per-destination copies.
    var destinationChains: (@MainActor (CaptureRecipe) -> [RecipeDestinationChain])?
    /// MCP: AI tools' window references.
    var windowResolver: (any RecipeWindowResolving)?
    /// MCP: excluded apps for AI tool captures.
    var aiToolCaptureGuard: (any RecipeAIToolCaptureGuard)?

    /// The app's parts the step executors use (settings, output, editors, capture, video).
    unowned let app: AppDelegate
    private let snapshot: RecipeSettingsSnapshot
    private var loading: Task<Void, Never>?
    private var changeObservers: [UUID: @MainActor () -> Void] = [:]
    /// What the app keeps per running flow (focus to give back, exports for the Notification step); RecipeRuntime+Flows.swift.
    var flowStates: [UUID: RecipeFlowAppState] = [:]
    /// Flows that will show the capture screen and haven't yet (RecipeRuntime+Selection.swift).
    var selectionReservations: Set<UUID> = []
    private var flowObservation: RecipeObservation?

    init(app: AppDelegate) {
        self.app = app
        let settings = app.settings
        let snapshot = RecipeSettingsSnapshot(settings.value)
        self.snapshot = snapshot
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? IPCEndpoint.defaultBundleIdentifier)
        recipesFolder = folder.appendingPathComponent("Recipes", isDirectory: true)
        // Locals first: no stored property is read before all are set.
        let trustStore = RecipeTrustStore(fileURL: folder.appendingPathComponent("recipe-trust.json"),
                                          secrets: KeychainSecretStore.shared)
        self.trustStore = trustStore
        let proxy = RecipeApproverProxy()
        approver = proxy
        let library = RecipeLibrary(loadSettings: { settings.value.recipes },
                                    saveSettings: { recipes in settings.update { $0.recipes = recipes } },
                                    trustStore: trustStore, approver: proxy, builtInRecipes: BuiltInRecipes.all,
                                    gates: { GateEnvironment(settings: settings.value) })
        self.library = library
        let steps = RecipeStepRegistry()
        self.steps = steps
        // The closures need the runtime, which doesn't exist yet: they reach it through the box, filled at the end.
        let box = RecipeRuntimeBox()
        let runner = RecipeRunner(steps: steps, environment: { SystemRecipeEnvironment(settings: snapshot.value) },
                                  preflight: { recipe in
                                      // Upstream CapturePipeline: the approval of a changed file first, then the automatic steps.
                                      guard let checked = await library.ensureApprovedAndCurrent(recipe) else { return nil }
                                      return await MainActor.run { box.runtime?.composed(checked) ?? checked }
                                  },
                                  recipeLookup: { id in
                                      await MainActor.run {
                                          guard let loaded = library.recipe(id: id), loaded.isEnabled else { return nil }
                                          return box.runtime?.composed(loaded.recipe) ?? loaded.recipe
                                      }
                                  },
                                  selectionInProgress: { CaptureOverlayController.isShowing || (box.runtime?.app.capture.isBusy ?? false) },
                                  bringSelectionToFront: { CaptureOverlayController.bringToFront() })
        self.runner = runner
        hub = RecipeTriggerHub(library: library, runner: runner)
        box.runtime = self
    }

    /// Recipes switched on (Settings › Recipes, upstream `EnableRecipeFeature`).
    var isEnabled: Bool { library.isFeatureEnabled }

    /// At launch, before the menus and the automation start: executors, settings observation, loading the files.
    func start() {
        guard Self.shared == nil else { return }
        Self.shared = self
        RecipeExecutors.register(on: self)
        app.settings.onChange(of: \AppSettings.self) { [snapshot] in snapshot.value = $0 }
        library.onChange = { [weak self] in self?.libraryChanged() }
        flowObservation = runner.addObserver { [weak self] event in
            Task { @MainActor in self?.flowEvent(event) }
        }
        loading = Task { [weak self] in
            guard let self else { return }
            _ = await self.library.reload()
            self.hub.sync()
        }
    }

    /// Waits until the recipe files of the settings are loaded (MCP's list/run, RUI's Open With routing).
    func whenLoaded() async {
        await loading?.value
    }

    /// At quit: no more triggers, running flows cancelled, no new flow starts (upstream `CaptureFlowRunner` on shutdown).
    func shutdown() {
        hub.stopAll()
        runner.running.forEach { $0.cancel() }
        let runner = runner
        Task.detached { await runner.shutdown() }
    }

    /// The menu bar's "Reload Recipes".
    func reload() async -> RecipeLoadResult {
        let result = await library.reload()
        hub.sync()
        return result
    }

    /// Called after recipes, approvals, option values or the switch changed (the one change signal: RUI's menus, the
    /// editor, the manager, MCP's tool list). Nobody else assigns `library.onChange`.
    func addChangeObserver(_ handler: @escaping @MainActor () -> Void) -> RecipeObservation {
        let id = UUID()
        changeObservers[id] = handler
        return RecipeObservation { [weak self] in
            Task { @MainActor in self?.changeObservers[id] = nil }
        }
    }

    /// The runner's events (RUI's failure notification, MCP's streaming).
    func addObserver(_ observer: @escaping @Sendable (RecipeFlowEvent) -> Void) -> RecipeObservation {
        runner.addObserver(observer)
    }

    /// Starts a prepared request (CLI, MCP, the recipe editor's test run).
    @discardableResult
    func start(_ request: RecipeRunRequest) -> RecipeFlowHandle {
        launch(request.recipe) { runner.start(request) } ?? .rejected(recipe: request.recipe, reason: Self.selectionOpen)
    }

    /// Starts a recipe by id (Recipes menu, forwarding); nil when it isn't there or is switched off.
    @discardableResult
    func start(recipeId: String, triggerType: String = WellKnownTriggerType.manual, variables: [String: JSONValue] = [:],
               objects: [String: any Sendable] = [:], payload: RecipePayload? = nil) -> RecipeFlowHandle? {
        guard library.recipe(id: recipeId)?.isEnabled == true,
              var request = library.runRequest(recipeId: recipeId, triggerType: triggerType) else { return nil }
        request.trigger = Self.triggerInfo(type: triggerType)
        request.variables = variables
        request.objects = objects
        request.payload = payload
        return launch(request.recipe) { runner.start(request) }
    }

    /// A trigger of RUI's sources fired.
    func fire(_ trigger: ActiveRecipeTrigger, info: RecipeTriggerInfo, variables: [String: JSONValue] = [:],
              objects: [String: any Sendable] = [:], payload: RecipePayload? = nil) -> RecipeFireOutcome {
        // The OpenFile trigger of a stock `recipe_file`: the app opens the file as it always did.
        if BuiltInRecipes.isDirectCapture(trigger.recipeId), route(builtIn: trigger.recipeId) == .direct { return .direct }
        guard let recipe = library.recipe(id: trigger.recipeId)?.recipe,
              let handle = launch(recipe, { hub.fire(trigger, info: info, variables: variables, objects: objects, payload: payload) }) else {
            return .notStarted
        }
        return .started(handle)
    }

    /// CaptureCoordinator / EditorManager / MenuBarActions hook: true when the recipe took the capture (started, or
    /// refused because the built-in is switched off); false: the caller captures as before.
    /// `byAutomation`: a command line, a link, AppleScript or Shortcuts started it; the recipe's capture screen then waits
    /// for a click (`OverlayInputArming`). The mark travels in the run request, not in a global that a delay could outlast.
    func interceptBuiltIn(_ capture: BuiltInCapture, byAutomation: Bool) -> Bool {
        var request = BuiltInCaptureRequest(capture, settings: app.settings.value)
        if byAutomation { request.objects[OverlayInputArming.automationMarkKey] = AutomationStartMark() }
        return intercept(request)
    }

    /// `interceptBuiltIn` for an entry point that sends the capture somewhere of its own: the menu bar's "capture the
    /// clipboard" and "Open Image from File…" go to `destinations` (the settings' destinations) whichever way they go
    /// (upstream `CaptureHelper`'s destination argument, `OverrideDestinations`). The app chooses them, not a caller.
    func interceptBuiltIn(_ capture: BuiltInCapture, destinations: [CaptureDestination]) -> Bool {
        var request = BuiltInCaptureRequest(capture, settings: app.settings.value)
        request.variables["OverrideDestinations"] = .array(RecipeDestinationsSnapshot.designations(destinations).map(JSONValue.string))
        return intercept(request)
    }

    private func intercept(_ request: BuiltInCaptureRequest) -> Bool {
        switch route(builtIn: request.recipeId) {
        case .direct:
            return false
        case .off:
            log.info("The built-in recipe '\(request.recipeId)' is switched off: nothing is captured.")
            NSSound.beep()
            return true
        case .recipe:
            startBuiltIn(request.recipeId, variables: request.variables, objects: request.objects)
            return true
        }
    }

    /// NotificationService hook: true when `recipe_notification` (changed) took the clicked capture; false: the picker.
    func offerNotificationCapture(_ capture: Capture) -> Bool {
        let id = BuiltInRecipes.notificationId
        switch route(builtIn: id) {
        case .direct:
            return false
        case .off:
            // Upstream `OfferCapture`: a switched-off recipe offers nothing more.
            return true
        case .recipe:
            var payload = RecipePayload(capture: capture, sourceType: "File")
            payload.metadata["source"] = .string("Notification")
            startBuiltIn(id, payload: payload)
            return true
        }
    }

    /// The browser extension's capture (upstream `CaptureHelper.ImportExtensionCapture`: the first active recipe with an
    /// Extension trigger for `browser`, else `recipe_browser_extension`; variables Capture and Browser). Nil: no flow
    /// started (recipes off, refused): BROWSER shows the destination picker instead.
    @discardableResult
    func importExtensionCapture(_ payload: RecipePayload, browser: String?) -> RecipeFlowHandle? {
        guard isEnabled else { return nil }
        let pick = RecipeExtensionCapturePick.pick(library.recipes, browser: browser)
        var variables: [String: JSONValue] = [:]
        if let browser, !browser.isEmpty { variables["Browser"] = .string(browser) }
        var objects: [String: any Sendable] = [:]
        // Upstream also hands the capture itself over as "Capture".
        objects["Capture"] = RecipeCaptureObject(payload: payload)
        if let index = pick.triggerIndex, let loaded = library.recipe(id: pick.recipeId),
           let trigger = library.activeTriggers(ofTypes: [WellKnownTriggerType.extension])
               .first(where: { recipeEquals($0.recipeId, loaded.recipe.id) && $0.index == index }) {
            var info = Self.triggerInfo(for: trigger)
            info.frontmostProcessID = nil
            if case .started(let handle) = fire(trigger, info: info, variables: variables, objects: objects, payload: payload) {
                return handle
            }
            return nil
        }
        return start(recipeId: pick.recipeId, triggerType: WellKnownTriggerType.extension, variables: variables,
                     objects: objects, payload: payload)
    }

    /// The host object for RUI's Editor trigger.
    func editorForm(for editor: EditorWindowController) -> RecipeEditorForm {
        RecipeEditorForm(editor: editor)
    }

    /// The trigger situation now, taken where the trigger fired: the frontmost app (nil when it is Greenshot) and the
    /// mouse in Quartz global points (upstream `FlowTriggerContext.Capture()`).
    static func triggerInfo(type: String, name: String? = nil, index: Int? = nil) -> RecipeTriggerInfo {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        return RecipeTriggerInfo(triggerType: type, triggerName: name, triggerIndex: index,
                                 frontmostProcessID: front == own ? nil : front, cursorLocation: ScreenSpace.mouseLocation)
    }

    /// `triggerInfo` for an active trigger.
    static func triggerInfo(for trigger: ActiveRecipeTrigger) -> RecipeTriggerInfo {
        triggerInfo(type: trigger.trigger.triggerType, name: trigger.trigger.name, index: trigger.index)
    }

    private func libraryChanged() {
        hub.sync()
        changeObservers.values.forEach { $0() }
    }

    // MARK: Built-in captures (CAP-012)

    /// The recipe as it runs: with its automatic steps (RMANAGER's composer), else as loaded.
    func composed(_ recipe: CaptureRecipe) -> CaptureRecipe {
        composeForRun?(recipe) ?? recipe
    }

    /// Which way a built-in capture goes now (`BuiltInCaptureRoute`).
    func route(builtIn id: String) -> BuiltInCaptureRoute {
        let loaded = library.recipe(id: id)
        return BuiltInCaptureRoute.decision(featureEnabled: isEnabled, loaded: loaded,
                                            composed: loaded.flatMap { composeForRun?($0.recipe) })
    }

    /// Starts a built-in recipe (upstream `CaptureHelper.Start`): its triggers don't matter, the trigger info is the
    /// moment of the hotkey or menu click.
    @discardableResult
    func startBuiltIn(_ id: String, variables: [String: JSONValue] = [:], objects: [String: any Sendable] = [:],
                      payload: RecipePayload? = nil) -> RecipeFlowHandle? {
        guard let loaded = library.recipe(id: id), loaded.isEnabled else { return nil }
        var request = RecipeRunRequest(recipe: loaded.recipe, trigger: Self.triggerInfo(type: WellKnownTriggerType.manual))
        request.variables = variables
        request.objects = objects
        request.payload = payload
        request.optionValues = library.optionValues
        log.info("Capturing with the recipe '\(id)' (it differs from the built-in one).")
        return launch(request.recipe) { runner.start(request) }
    }
}

/// The runtime for the runner's closures, which are made before the runtime exists.
final class RecipeRuntimeBox: @unchecked Sendable {
    @MainActor weak var runtime: RecipeRuntime?
}

/// A built-in capture as a recipe start: the recipe and what the caller hands over (upstream `CaptureHelper`).
struct BuiltInCaptureRequest {
    var recipeId: String
    var variables: [String: JSONValue] = [:]
    var objects: [String: any Sendable] = [:]

    @MainActor
    init(_ capture: BuiltInCapture, settings: AppSettings) {
        switch capture {
        case .region: recipeId = BuiltInRecipes.regionId
        case .window: recipeId = BuiltInRecipes.windowId
        case .activeWindow: recipeId = BuiltInRecipes.activeWindowId
        case .windowFromList(let window):
            recipeId = BuiltInRecipes.activeWindowId
            objects["TargetWindow"] = RecipeWindowObject(window: window)
        case .fullScreen(let display):
            recipeId = BuiltInRecipes.fullScreenId
            if let display {
                objects["TargetDisplay"] = RecipeDisplayObject(displayID: display)
            } else {
                // The menu's "All Screens" (upstream `CaptureFullscreen(…, ScreenCaptureMode.FullScreen)`).
                variables["ScreenCaptureMode"] = .string("FullScreen")
            }
        case .fullScreenFromHotkey: recipeId = BuiltInRecipes.fullScreenId
        case .lastRegion: recipeId = BuiltInRecipes.lastRegionId
        case .text: recipeId = BuiltInRecipes.ocrId
        case .clipboard: recipeId = BuiltInRecipes.clipboardId
        case .file(let url):
            recipeId = BuiltInRecipes.fileId
            variables["Filename"] = .string(url.path)
        }
    }
}
