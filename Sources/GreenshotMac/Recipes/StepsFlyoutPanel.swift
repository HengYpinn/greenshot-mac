// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

private let log = Log("Recipes")

/// The DynamicDestination step's flyout (upstream `DynamicDestinationWindow`): the capture's thumbnail (a click shows it
/// big, Esc or a click returns), the core destinations as tiles, the other destinations with a search field, the
/// recipes to forward the capture to, the failed export's message with a "Retry" badge on Clipboard, and the countdown
/// "Auto-closing in Ns" (TimeoutSeconds). It moves when dragged by its background; Esc closes it.
struct RecipeFlyoutPresenter: RecipeFlyoutPresenting {
    let runtime: RecipeRuntime
    let steps: RecipeStepRegistry

    func availableDestinations(in context: RecipeFlowContext) async -> [(designation: String, name: String)] {
        await MainActor.run { Self.destinations(settings: runtime.app.settings.value) }
    }

    /// The destinations as the picker offers them (by priority, an administrator's turned-off ones left out), and the
    /// external commands one by one.
    @MainActor
    static func destinations(settings: AppSettings) -> [(designation: String, name: String)] {
        var list: [(designation: String, name: String)] = []
        let ordered = CaptureDestination.allCases.filter { $0 != .picker && !settings.isDestinationExcluded($0) }
            .sorted { ($0.pickerPriority, $0.pickerTitle) < ($1.pickerPriority, $1.pickerTitle) }
        for destination in ordered {
            if destination == .externalCommand {
                for command in settings.externalCommands { list.append(("External \(command.name)", command.name)) }
                continue
            }
            let title = destination.pickerTitle
            list.append((RecipeDestinationDesignation.designation(for: destination), title.hasSuffix("…") ? String(title.dropLast()) : title))
        }
        return list
    }

    func forwardableRecipes() async -> [RecipeFlyout.RecipeForwardChoice] {
        await MainActor.run {
            // A built-in recipe's name in the language of the app (L10nText.display); a file's as it is.
            runtime.library.recipes.filter { $0.isEnabled && !$0.recipe.isAIToolRecipe }
                .map { RecipeFlyout.RecipeForwardChoice(id: $0.recipe.id, name: $0.isBuiltIn ? L10nText.display($0.recipe.name) : $0.recipe.name) }
        }
    }

    func choose(_ flyout: RecipeFlyout, preview: CGImage?, in context: RecipeFlowContext) async throws -> RecipeFlyout.Choice {
        let handle = RecipeFlyoutHandle()
        let choice = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<RecipeFlyout.Choice, Never>) in
                Task { @MainActor in
                    // Cancelled before the flyout was there: none is shown (R-F5).
                    guard !handle.cancelled else { return continuation.resume(returning: .dismissed) }
                    let state = runtime.flowState(context.executionId)
                    state.waitsFor = .destination
                    handle.controller = RecipeFlyoutPanel.show(flyout, preview: preview) { choice in
                        state.waitsFor = nil
                        continuation.resume(returning: choice)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                handle.cancelled = true
                handle.controller?.close()
            }
        }
        try Task.checkCancellation()
        return choice
    }

    /// The chosen destination like a destination step with that designation (its automatic steps, its errors).
    func export(_ designation: String, step: RecipeStepInvocation, in context: RecipeFlowContext) async throws {
        guard let payload = context.payload else { return }
        let exporter = RecipeAppExporter(runtime: runtime)
        guard var target = await exporter.target(for: designation, step: step, in: context) else {
            context.log("Warning: no destination '\(designation)' here.")
            return
        }
        // The user clicked it: a Jira or Confluence token kept without its server is asked about, whoever started the flow.
        target.pickedByUser = true
        let chains = await MainActor.run { runtime.destinationChains?(context.recipe) ?? [] }
        var copies = RecipeDestinationCopies(chains: chains, steps: steps)
        let copy = await copies.payload(for: designation, original: payload, in: context)
        let result = await exporter.export(copy, to: target, step: step, in: context)
        guard result.status != .declined else { return }
        context.exports.add(RecipeExportOutcome(designation: designation, succeeded: result.isSucceeded,
                                                target: result.fileURL?.path ?? result.target, uri: result.link,
                                                errorMessage: result.error))
        if result.status == .failed {
            let failures = [(designation: designation, error: result.error ?? "unknown error")]
            context[variable: "DestinationExportErrors"] = .string(RecipeDestinationPlan.errorsText(failures))
            if let error = RecipeDestinationPlan.failure(failures) { throw error }
        }
    }

    /// Upstream: the capture goes to the other recipe with this flow's variables, which must not capture or select again.
    /// `OverrideDestinations` stays here: the other recipe was approved for its own destinations.
    func forward(to recipeId: String, in context: RecipeFlowContext) async {
        guard let payload = context.payload else { return }
        var variables: [String: JSONValue] = [:]
        // Not where this flow sends or saved its capture: `OverrideDestinations` (the other recipe was approved for its
        // own destinations) and `Destination.*` (this flow's files, R-F8).
        for member in context.variables where !Self.staysHere(member.key) { variables[member.key] = member.value }
        let handed = variables
        let handle = await MainActor.run {
            runtime.start(recipeId: recipeId, triggerType: WellKnownTriggerType.manual, variables: handed, payload: payload)
        }
        guard let handle else {
            context.log("DynamicDestination: the recipe '\(recipeId)' isn't there or is switched off.")
            return
        }
        let result = await handle.result
        context.log("DynamicDestination: the recipe '\(recipeId)' ended: \(result.state.rawValue)")
    }
}

extension RecipeFlyoutPresenter {
    static func staysHere(_ name: String) -> Bool {
        recipeEquals(name, "OverrideDestinations") || name.lowercased().hasPrefix("destination.")
    }
}

/// The open flyout of a flow, so a cancelled flow can close it.
final class RecipeFlyoutHandle: @unchecked Sendable {
    @MainActor var controller: RecipeFlyoutPanel?
    @MainActor var cancelled = false
}

@MainActor
final class RecipeFlyoutModel: ObservableObject {
    let flyout: RecipeFlyout
    let preview: NSImage?
    let dimensions: String?
    @Published var secondsLeft: Int
    @Published var search = ""
    @Published var recipeId: String
    @Published var showsFullPreview = false
    var choose: (RecipeFlyout.Choice) -> Void = { _ in }

    init(flyout: RecipeFlyout, preview: CGImage?) {
        self.flyout = flyout
        self.preview = preview.map { NSImage(cgImage: $0, size: .zero) }
        dimensions = preview.map { "\($0.width) × \($0.height) px" }
        secondsLeft = flyout.timeoutSeconds
        recipeId = flyout.recipes.first?.id ?? ""
    }

    func symbol(_ designation: String) -> String {
        if recipeEqualsDesignation(designation, "Editor") { return CaptureDestination.editor.symbolName }
        return RecipeDestinationPlan.destination(of: designation).destination?.symbolName ?? "square.and.arrow.up"
    }

    private func recipeEqualsDesignation(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}

struct RecipeFlyoutView: View {
    @ObservedObject var model: RecipeFlyoutModel

    var body: some View {
        ZStack {
            content
            if model.showsFullPreview, let preview = model.preview {
                fullPreview(preview)
            }
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.flyout.title).font(.title3.weight(.semibold))
                Spacer()
                Button { model.choose(.dismissed) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            if let error = model.flyout.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Select an alternative destination below, forward to another recipe, or retry:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let preview = model.preview {
                HStack(alignment: .bottom, spacing: 10) {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                        .onTapGesture { model.showsFullPreview = true }
                        .help("Click to view full preview (Esc to exit)")
                    if let dimensions = model.dimensions {
                        Text(dimensions).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            let core = model.flyout.tiles.filter(\.isCore)
            if !core.isEmpty {
                Text("Core Destinations").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(core, id: \.designation) { tile($0) }
                }
            }
            let others = model.flyout.otherTiles(matching: model.search)
            if !model.flyout.tiles.filter({ !$0.isCore }).isEmpty {
                HStack {
                    Text("Destinations (\(others.count))").font(.headline)
                    Spacer()
                    TextField("Search", text: $model.search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(others, id: \.designation) { tile($0) }
                    }
                }
                .frame(maxHeight: 150)
            }
            if !model.flyout.recipes.isEmpty {
                Text("Forward to recipe").font(.headline)
                HStack {
                    Picker("", selection: $model.recipeId) {
                        ForEach(model.flyout.recipes, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    Button("▶ Run Recipe") { model.choose(.forward(model.recipeId)) }
                        .disabled(model.recipeId.isEmpty)
                }
            }
            HStack {
                let countdown = RecipeFlyout.countdownText(model.secondsLeft)
                if !countdown.isEmpty {
                    Text(countdown).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { model.choose(.dismissed) }
            }
        }
        .padding(16)
    }

    private func tile(_ tile: RecipeFlyoutTile) -> some View {
        Button {
            model.choose(recipeEquals(tile.designation, "Editor") ? .editor : .destination(tile.designation))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.symbol(tile.designation))
                    .frame(width: 22)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    // The badge below the title when both don't fit on one line (longer languages).
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            Text(tile.title).font(.body.weight(.medium)).lineLimit(1)
                            badge(tile)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tile.title).font(.body.weight(.medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            badge(tile)
                        }
                    }
                    Text(tile.subtitle).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func badge(_ tile: RecipeFlyoutTile) -> some View {
        if let badge = tile.badge {
            Text(badge)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.25))
                .clipShape(Capsule())
        }
    }

    private func fullPreview(_ preview: NSImage) -> some View {
        ZStack {
            Color.black.opacity(0.85)
            VStack(spacing: 8) {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
                Text("Click anywhere or press Esc to return").font(.callout).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.bottom, 10)
        }
        .onTapGesture { model.showsFullPreview = false }
    }

    private func recipeEquals(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}

/// The flyout's panel and its countdown; `done` gets the choice once.
@MainActor
final class RecipeFlyoutPanel: NSObject, NSWindowDelegate {
    private static var open: [RecipeFlyoutPanel] = []

    private let panel: RecipeKeyPanel
    private let model: RecipeFlyoutModel
    private var timer: Timer?
    /// The window is closing by its close button: it mustn't be closed again.
    private var closing = false
    private var done: ((RecipeFlyout.Choice) -> Void)?

    static func show(_ flyout: RecipeFlyout, preview: CGImage?, done: @escaping (RecipeFlyout.Choice) -> Void) -> RecipeFlyoutPanel {
        let controller = RecipeFlyoutPanel(flyout: flyout, preview: preview, done: done)
        open.append(controller)
        controller.place()
        NSApp.activate()
        controller.panel.makeKeyAndOrderFront(nil)
        controller.startCountdown()
        return controller
    }

    private init(flyout: RecipeFlyout, preview: CGImage?, done: @escaping (RecipeFlyout.Choice) -> Void) {
        model = RecipeFlyoutModel(flyout: flyout, preview: preview)
        self.done = done
        let hosting = NSHostingView(rootView: RecipeFlyoutView(model: model))
        hosting.layoutSubtreeIfNeeded()
        panel = RecipeKeyPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        super.init()
        panel.title = "Greenshot - \(flyout.title)"
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.escape() }
        model.choose = { [weak self] choice in self?.finish(choice) }
    }

    /// Near the mouse, on its display.
    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        var origin = CGPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height / 2)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func startCountdown() {
        guard model.secondsLeft > 0 else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.secondsLeft -= 1
                if self.model.secondsLeft <= 0 { self.finish(.dismissed) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Esc closes the big preview first, then the flyout (upstream `OnWindowKeyDown`).
    private func escape() {
        if model.showsFullPreview {
            model.showsFullPreview = false
        } else {
            finish(.dismissed)
        }
    }

    func close() {
        finish(.dismissed)
    }

    private func finish(_ choice: RecipeFlyout.Choice) {
        timer?.invalidate()
        timer = nil
        guard let done else { return }
        self.done = nil
        log.debug("Flyout choice: \(choice)")
        done(choice)
        panel.delegate = nil
        if !closing { panel.close() }
        Self.open.removeAll { $0 === self }
    }

    func windowWillClose(_ notification: Notification) {
        closing = true
        finish(.dismissed)
    }
}
