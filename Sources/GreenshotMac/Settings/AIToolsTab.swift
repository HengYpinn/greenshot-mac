// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by MCP after the wave 4 prep.

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › AI Tools (AUT-085, APP-096; upstream `Ai/Views/AiToolsSettingsPage.xaml`): the opt-in switch with
/// greenshot-mcp's place and how to connect an AI tool, the allowed programs, the programs refused until the app quits,
/// what AI tools may do, the applications they never see, and the approved recipes (RCP-205). Shown always: the Mac has
/// no beta-tester switch, and AI tools are off until switched on here.
struct AIToolsSettingsTab: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var model: AIToolsTabModel
    @State private var newExcluded = ""
    @State private var setupClient: AIToolSetupClient = .claudeCode
    @State private var copied: String?

    init(store: SettingsStore, model: AIToolsTabModel? = nil) {
        self.store = store
        _model = StateObject(wrappedValue: model ?? AIToolsTabModel())
    }

    var body: some View {
        Form {
            accessSection
            connectSection
            programsSection
            if !model.denied.isEmpty { deniedSection }
            permissionsSection
            excludedSection
            approvedSection
        }
        .formStyle(.grouped)
        .onAppear { model.refresh(store: store) }
        .onChange(of: store.value.aiTools.allowedClients) { _, _ in model.refresh(store: store) }
    }

    // MARK: Access

    private var accessSection: some View {
        Section {
            Toggle("Let AI tools use Greenshot", isOn: store.binding(\.aiTools.enabled))
                .managed(\.aiTools.enabled)
            Text("AI tools (like Claude Code, Claude Desktop, VS Code or Cursor) connect through greenshot-mcp, which comes with \(AppInfo.name). They can list your windows, take screenshots and run your recipes. While this is off, Greenshot refuses every request without asking. Each program still needs your permission the first time it connects.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("MCP server") {
                if let path = model.serverPath {
                    HStack(spacing: 6) {
                        Text("✔").foregroundStyle(.green)
                        Text(DiagnosticReport.abbreviatingHome(path))
                            .font(.caption.monospaced()).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing)
                        Button(copied == "path" ? "Copied" : "Copy Path") { copy(path, as: "path") }
                    }
                } else {
                    HStack(spacing: 6) {
                        Text("✘").foregroundStyle(.red)
                        Text("greenshot-mcp was not found next to the app").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Access")
        }
    }

    private var connectSection: some View {
        Section {
            Picker("AI tool", selection: $setupClient) {
                ForEach(AIToolSetupClient.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            if let path = model.serverPath {
                let snippet = setupClient.snippet(serverPath: path)
                Text(snippet)
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(setupClient.instructions).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(copied == setupClient.rawValue ? "Copied" : "Copy") { copy(snippet, as: setupClient.rawValue) }
                }
            } else {
                Text("Build greenshot-mcp (swift build) or use the app from scripts/build-app.sh to connect an AI tool.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Connect an AI tool")
        } footer: {
            Text("Each AI tool starts greenshot-mcp itself. Restart the AI tool or reload its MCP servers after changing its configuration.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Programs

    private var programsSection: some View {
        Section {
            if store.consentStatus.needsAttention { consentNotice(store.consentStatus) }
            if store.value.aiTools.allowedClients.isEmpty && !store.consentStatus.isUnverifiable {
                Text("No program is allowed yet.").foregroundStyle(.secondary)
            }
            ForEach(store.value.aiTools.allowedClients, id: \.self) { line in
                let entry = AIToolAllowedEntry(parsing: line)
                HStack(alignment: .top) {
                    programLabel(executable: entry.executable, script: entry.script,
                                 signer: entry.teamID.map { String(localized: "Team ID: \($0)") } ?? String(localized: "No developer signature kept"))
                    Spacer()
                    Button {
                        store.update { $0.aiTools.allowedClients.removeAll { $0 == line } }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove: the program is asked again the next time it connects.")
                }
            }
            .managed(\.aiTools.allowedClients)
        } header: {
            Text("Allowed programs")
        } footer: {
            Text("These programs may use Greenshot. Remove one with ✕ to be asked again the next time it connects. For a runtime (node, python, …) only the script it runs is allowed, and a program signed by a developer only while it is still signed by the same one.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The consent couldn't be checked, or a change couldn't be sealed (a locked Keychain): what that means, why, and
    /// Retry (`SettingsStore.retryConsent`).
    private func consentNotice(_ status: AIToolsConsentKeeper.Status) -> some View {
        var lines: [String] = []
        if status.isUnverifiable {
            lines.append(String(localized: "Greenshot can't check which programs you allowed: it can't read the key of their seal from the Keychain. Until it can, AI tools are asked as if no program were allowed."))
            if !status.isStoredUnsealed {
                lines.append(String(localized: "The programs you allowed are kept and count again once it can."))
            }
        }
        if status.isStoredUnsealed {
            lines.append(String(localized: "The AI tools consent is saved without its seal because the Keychain couldn't be used: after the next start, every program is asked again."))
        }
        if status.hasChangesUntilQuit {
            lines.append(String(localized: "Changes made while the Keychain couldn't be used apply only until Greenshot quits."))
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("⚠ " + lines.joined(separator: " "))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top) {
                if let problem = status.problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Retry") { store.retryConsent() }
            }
        }
    }

    private var deniedSection: some View {
        Section {
            ForEach(model.denied, id: \.key) { client in
                HStack(alignment: .top) {
                    programLabel(executable: client.path, script: client.identity.script, signer: client.signerText)
                    Spacer()
                    Button("Allow") { model.allowDenied(client, store: store) }
                        .disabled(store.isLocked(\AppSettings.aiTools.allowedClients))
                    Button("Ask Again") { model.askAgain(client, store: store) }
                }
            }
        } header: {
            Text("Not allowed until Greenshot quits")
        } footer: {
            Text("You answered \"Don't Allow\" (or closed the question) for these programs, so Greenshot refuses them without asking. Allow one here, or let Greenshot ask again the next time it connects.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func programLabel(executable: String, script: String?, signer: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AIToolCaller.displayName(forExecutable: executable)).fontWeight(.semibold)
            Text(AIToolText.displayed(DiagnosticReport.abbreviatingHome(executable), limit: 300)).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).help(AIToolText.displayed(executable, limit: 1000))
            if let script {
                Text(String(localized: "Script: \(AIToolText.displayed(DiagnosticReport.abbreviatingHome(script), limit: 300))")).font(.caption)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(AIToolText.displayed(script, limit: 1000))
            }
            Text(signer).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Permissions and exclusions

    private var permissionsSection: some View {
        Section("What AI tools may do") {
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Let AI tools propose recipes", isOn: store.binding(\.aiTools.allowRecipeProposals))
                    .managed(\.aiTools.allowRecipeProposals)
                Text("You see every proposed recipe and decide whether to approve it. Its triggers and risky actions start switched off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Show a notification when an AI tool takes a screenshot", isOn: store.binding(\.aiTools.notifyOnCapture))
                .managed(\.aiTools.notifyOnCapture)
        }
    }

    private var excludedSection: some View {
        Section {
            ForEach(store.value.aiTools.excludedApplications, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Button("Remove") { store.update { $0.aiTools.excludedApplications.removeAll { $0 == name } } }
                        .buttonStyle(.borderless)
                }
            }
            .managed(\.aiTools.excludedApplications)
            HStack {
                TextField("Application", text: $newExcluded, prompt: Text("An application, like KeePassXC or com.example.vault"))
                    .labelsHidden()
                    .onSubmit(addExcluded)
                    .help("An application's name or bundle identifier; Return adds it")
                Button("Add", action: addExcluded)
                    .disabled(newExcluded.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .managed(\.aiTools.excludedApplications)
        } header: {
            Text("Never share these applications")
        } footer: {
            Text("Windows of these applications are never listed or captured for AI tools, and they are blacked out in screenshots AI tools take. Names are application names or bundle identifiers; upper and lower case, spaces and \".app\" don't matter.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addExcluded() {
        // Several at once are fine too: "KeePassXC, Bitwarden"
        let names = newExcluded.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.update { settings in
            for name in names where !settings.aiTools.excludedApplications.contains(where: { AIToolExclusion.normalize($0) == AIToolExclusion.normalize(name) }) {
                settings.aiTools.excludedApplications.append(name)
            }
        }
        newExcluded = ""
    }

    // MARK: Approved recipes

    private var approvedSection: some View {
        Section {
            if model.approved.isEmpty {
                Text("No recipes from files.").foregroundStyle(.secondary)
            }
            ForEach(model.approved, id: \.recipeId) { row in
                HStack(alignment: .top) {
                    if row.needsAttention { Text("⚠").help("Not approved, changed since its approval, or triggers left off") }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).fontWeight(.semibold)
                        Text(row.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Details") { model.showDetails(row) }
                    Button("Review…") { model.review(row, store: store) }
                    Button("Revoke") { model.revoke(row, store: store) }
                }
            }
        } header: {
            Text("Approved recipes")
        } footer: {
            Text("Recipes from files, also those written by AI tools, and what you approved for them. Changes here take effect right away.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func copy(_ text: String, as key: String) {
        // Through Clipboard: the write is recorded as Greenshot's own (recipe Clipboard triggers ignore it).
        Clipboard.copy(text: text)
        copied = key
    }
}

/// What the tab shows beyond the settings: greenshot-mcp's place, the programs refused in this run, the signers and the
/// approved recipes, from the running app (`AIToolsCenter.shared`, `RecipeRuntime.shared`); fixed values for the
/// snapshots.
@MainActor
final class AIToolsTabModel: ObservableObject {
    @Published var serverPath: String?
    @Published var denied: [AIToolClient] = []
    @Published var approved: [AIToolApprovedRecipe] = []
    private let isSample: Bool
    private var observation: RecipeObservation?

    /// `serverPath` nil: greenshot-mcp of this app (`installedServerPath`); "" for none (snapshots).
    init(serverPath: String? = nil, denied: [AIToolClient]? = nil, approved: [AIToolApprovedRecipe]? = nil) {
        self.serverPath = serverPath.map { $0.isEmpty ? nil : $0 } ?? Self.installedServerPath
        isSample = denied != nil || approved != nil
        self.denied = denied ?? []
        self.approved = approved ?? []
    }

    /// `Contents/Helpers/greenshot-mcp` of the app bundle, or `greenshot-mcp` next to a bare build.
    static var installedServerPath: String? {
        if Snapshots.requestedFolder != nil { return snapshotServerPath }
        let executable = IPCEndpoint.currentExecutablePath
        let path: String
        if let bundle = IPCPeerPolicy.appBundle(ofExecutable: executable) {
            path = (bundle as NSString).appendingPathComponent("Contents/Helpers/greenshot-mcp")
        } else {
            path = ((executable as NSString).deletingLastPathComponent as NSString).appendingPathComponent("greenshot-mcp")
        }
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static let snapshotServerPath = "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp"

    func refresh(store: SettingsStore) {
        guard !isSample else { return }
        if let center = AIToolsCenter.shared { denied = center.deniedClients }
        guard let recipes = RecipeRuntime.shared else { return }
        if observation == nil {
            observation = recipes.addChangeObserver { [weak self] in self?.refresh(store: store) }
        }
        let library = recipes.library
        // Recipes and automatic steps from files, each with its own approval (MC-M4)
        let recipeRows = library.recipes.filter { !$0.isBuiltIn }.map { loaded in
            AIToolApprovedRecipe(recipeId: loaded.recipe.id, name: loaded.recipe.name, isExtension: false,
                                 details: library.details(recipeId: loaded.recipe.id))
        }
        let stepRows = library.extensions.filter { !$0.isBuiltIn }.map { loaded in
            AIToolApprovedRecipe(recipeId: loaded.recipe.id, name: loaded.recipe.name, isExtension: true,
                                 details: library.extensionDetails(id: loaded.recipe.id))
        }
        approved = recipeRows + stepRows
    }

    func allowDenied(_ client: AIToolClient, store: SettingsStore) {
        AIToolsCenter.shared?.allowDenied(client)
        refresh(store: store)
    }

    func askAgain(_ client: AIToolClient, store: SettingsStore) {
        AIToolsCenter.shared?.askAgain(client)
        refresh(store: store)
    }

    /// Details: the approval sheet, read only.
    func showDetails(_ row: AIToolApprovedRecipe) {
        guard let recipes = RecipeRuntime.shared else { return }
        let library = recipes.library
        guard let request = row.isExtension ? library.extensionDetailsRequest(id: row.recipeId) : library.detailsRequest(recipeId: row.recipeId) else {
            Self.alert(String(localized: "The details of \u{201C}\(row.title)\u{201D} aren't available: it isn't loaded any more."))
            return
        }
        Task { _ = await recipes.approver.requestApproval(request) }
    }

    /// Review: the approval sheet to change the switches or revoke it; takes effect at once.
    func review(_ row: AIToolApprovedRecipe, store: SettingsStore) {
        guard let recipes = RecipeRuntime.shared else { return }
        let library = recipes.library
        Task {
            let result = row.isExtension ? await library.reviewExtensionApproval(id: row.recipeId)
                                         : await library.reviewApproval(recipeId: row.recipeId)
            if !result.isValid { Self.alert(result.errors.joined(separator: "\n")) }
            refresh(store: store)
        }
    }

    /// Revoke, after asking: it stops running at once and isn't loaded again; its file stays.
    func revoke(_ row: AIToolApprovedRecipe, store: SettingsStore) {
        guard let recipes = RecipeRuntime.shared else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Revoke the approval of \u{201C}\(row.title)\u{201D}?")
        alert.informativeText = String(localized: "It stops running right away and isn't loaded again. Its file stays where it is: open it again to review and approve it.")
        alert.addButton(withTitle: String(localized: "Keep", comment: "Keeps the approval of a recipe"))
        alert.addButton(withTitle: String(localized: "Revoke"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let revoked = row.isExtension ? recipes.library.revokeExtensionApproval(id: row.recipeId)
                                      : recipes.library.revokeApproval(recipeId: row.recipeId)
        if !revoked {
            Self.alert(String(localized: "The approval of \u{201C}\(row.title)\u{201D} could not be revoked. It is unchanged; see the log for why."))
        }
        refresh(store: store)
    }

    private static func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Approved recipes")
        alert.informativeText = text
        alert.runModal()
    }
}
