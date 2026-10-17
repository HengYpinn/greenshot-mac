// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The approval window's content (upstream `RecipeApprovalWindow.xaml`): what the recipe does in Greenshot's words, its
/// triggers and permissions with their switches, the changes, the AI tool's words marked as such, and the buttons.
struct RecipeApprovalView: View {
    @ObservedObject var model: RecipeApprovalModel
    /// False for `--snapshot`: the whole content at its height, without a scroll view.
    var scrolls = true

    private var sheet: RecipeApprovalSheet { model.sheet }

    var body: some View {
        VStack(spacing: 0) {
            if scrolls {
                ScrollView { content }
            } else {
                content
                Spacer(minLength: 0)
            }
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if let overlay = model.overlay {
                RecipeApprovalOverlayView(model: model, overlay: overlay)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if sheet.style == .validationError { problemsCard }
            if sheet.previousApprovedAt != nil { historyCard }
            if sheet.proposedBy != nil { aiCard }
            if let title = sheet.changesTitle { changesCard(title) }
            overviewCard
            if !sheet.extensionReach.isEmpty { reachCard }
            if !sheet.isExtension, sheet.style != .validationError { triggersCard }
            if !sheet.steps.isEmpty { stepsCard }
            if !sheet.gates.isEmpty { gatesCard }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: sheet.icon)
                .font(.system(size: 28))
                .foregroundStyle(ApprovalColors.color(sheet.badgeTone))
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sheet.headerTitle).font(.title2.bold())
                    ApprovalBadge(text: sheet.badge, tone: sheet.badgeTone)
                }
                Text(sheet.headerDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cards

    private var problemsCard: some View {
        ApprovalCard(title: "What is wrong", tone: .error) {
            ForEach(Array(sheet.problems.enumerated()), id: \.offset) { _, problem in
                VStack(alignment: .leading, spacing: 3) {
                    Text(problem.message).fontWeight(.semibold).textSelection(.enabled)
                    if let hint = problem.hint {
                        Text("What to change: \(hint)").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let hint = sheet.overallHint, !sheet.problems.contains(where: { $0.hint == hint }) {
                Text(hint).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var historyCard: some View {
        let changed = sheet.style == .modified
        return ApprovalCard(title: changed ? "The file changed since you approved it" : "Your approval", tone: changed ? .warning : .neutral) {
            if let date = sheet.previousApprovedAt {
                ApprovalField(label: "Approved", value: date.formatted(date: .abbreviated, time: .standard))
            }
            if let hash = sheet.previousHash {
                ApprovalField(label: "Approved SHA-256", value: hash, monospaced: true)
                if hash.caseInsensitiveCompare(sheet.fileHash) != .orderedSame {
                    ApprovalField(label: "File SHA-256", value: sheet.fileHash, monospaced: true)
                }
            }
            HStack {
                if sheet.hasDiff {
                    Button("View Changes") { model.changedLinesOnly = true; model.overlay = .changes }
                }
                Button("View \(sheet.titleNoun) JSON") { model.overlay = .json }
            }
        }
    }

    private var aiCard: some View {
        let isProposal = sheet.style == .aiProposal
        return ApprovalCard(title: isProposal ? "Proposed by an AI tool" : "Written by an AI tool", tone: .warning) {
            Text(sheet.proposedBy ?? "").fontWeight(.semibold).textSelection(.enabled)
            if let request = sheet.aiRequest {
                AIWords(label: "What it was asked (the AI tool's words, not checked by Greenshot):", text: request)
            }
            if let explanation = sheet.aiExplanation {
                AIWords(label: "Its explanation (the AI tool's words, not checked by Greenshot):", text: explanation)
            }
            Text("Trust what Greenshot writes below about the \(sheet.noun), not these words.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func changesCard(_ title: String) -> some View {
        ApprovalCard(title: title, tone: sheet.request.replacesBuiltIn ? .accent : .warning) {
            ForEach(Array(sheet.changeLines.enumerated()), id: \.offset) { _, line in
                Text(line).fixedSize(horizontal: false, vertical: true)
            }
            if sheet.hasDiff, sheet.previousApprovedAt == nil {
                Button("View Changes") { model.changedLinesOnly = true; model.overlay = .changes }
            }
        }
    }

    private var overviewCard: some View {
        ApprovalCard(title: nil, tone: .neutral) {
            HStack(alignment: .firstTextBaseline) {
                Text(sheet.recipeName).font(.headline)
                if !sheet.recipeVersion.isEmpty { Text(sheet.recipeVersion).font(.caption).foregroundStyle(.secondary) }
            }
            Text(sheet.recipeDescription).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ApprovalField(label: sheet.isExtension ? "ID" : "Recipe ID", value: sheet.recipeId)
            HStack(alignment: .firstTextBaseline) {
                ApprovalField(label: "File", value: sheet.fileText)
                if sheet.request.fileURL != nil {
                    Button("Show in Finder") { model.showInFinder() }.controlSize(.small)
                }
            }
            ApprovalField(label: "SHA-256", value: sheet.fileHash, monospaced: true)
            if sheet.previousApprovedAt == nil, !sheet.request.content.isEmpty {
                Button("View \(sheet.titleNoun) JSON") { model.overlay = .json }
            }
        }
    }

    private var reachCard: some View {
        ApprovalCard(title: "Changes other recipes", tone: .warning) {
            ForEach(Array(sheet.extensionReach.enumerated()), id: \.offset) { _, line in
                Text(line).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var triggersCard: some View {
        ApprovalCard(title: "Triggers", tone: .neutral) {
            if sheet.triggers.isEmpty {
                Text("No trigger: the recipe runs from the recipe list, the command line or another recipe.")
                    .foregroundStyle(.secondary)
            } else {
                if !model.isReadOnly {
                    Text(sheet.triggerHint)
                        .font(.callout)
                        .foregroundStyle(sheet.triggerHintIsWarning ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(sheet.triggers) { trigger in
                    ApprovalSwitch(title: trigger.title, explanation: trigger.explanation, isOn: model.binding(trigger: trigger.id))
                        .disabled(model.isReadOnly)
                }
            }
        }
    }

    private var stepsCard: some View {
        ApprovalCard(title: "What it does (written by Greenshot from the \(sheet.noun))", tone: .neutral) {
            ForEach(Array(sheet.steps.enumerated()), id: \.offset) { _, line in
                ApprovalStepLine(line: line)
            }
        }
    }

    private var gatesCard: some View {
        ApprovalCard(title: "Permissions", tone: sheet.isApproveEnabled ? .neutral : .warning) {
            if !model.isReadOnly {
                Text("The \(sheet.noun) is only used with every permission it needs.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(sheet.gates) { gate in
                VStack(alignment: .leading, spacing: 3) {
                    ApprovalSwitch(title: gate.question, explanation: gate.explanation, isOn: model.binding(gate: gate.gate))
                        .disabled(model.isReadOnly)
                    ForEach(gate.targets, id: \.self) { target in
                        Text("• " + target)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.leading, 22)
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if sheet.offersOpenInEditor {
                Toggle("Open in the recipe editor after saving", isOn: $model.openInEditor)
                    .toggleStyle(.checkbox)
            }
            Spacer()
            buttons
        }
        // Under a viewer the buttons are covered: Esc and Return belong to the viewer then.
        .disabled(model.overlay != nil)
    }

    @ViewBuilder private var buttons: some View {
        switch sheet.style {
        case .validationError:
            if sheet.request.fileURL != nil {
                Button("Edit Recipe File") { model.editFile() }
            }
            Button("Close") { model.close() }.keyboardShortcut(.defaultAction)
        case .details:
            Button("Close") { model.close() }.keyboardShortcut(.defaultAction)
        case .review:
            Button(sheet.rejectTitle, role: .destructive) { model.reject() }
            Button("Keep as Is") { model.close() }.keyboardShortcut(.cancelAction)
            Button(sheet.approveTitle) { model.approve() }
                .keyboardShortcut(.defaultAction)
                .disabled(!sheet.isApproveEnabled)
        default:
            Button(sheet.rejectTitle) { model.reject() }.keyboardShortcut(.cancelAction)
            Button(sheet.approveTitle) { model.approve() }
                .keyboardShortcut(.defaultAction)
                .disabled(!sheet.isApproveEnabled)
        }
    }
}

// MARK: Parts

enum ApprovalColors {
    static func color(_ tone: RecipeApprovalSheet.Tone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .accent: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct ApprovalBadge: View {
    let text: String
    let tone: RecipeApprovalSheet.Tone

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(ApprovalColors.color(tone))
            .background(RoundedRectangle(cornerRadius: 4).fill(ApprovalColors.color(tone).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ApprovalColors.color(tone).opacity(0.5), lineWidth: 1))
    }
}

struct ApprovalCard<Content: View>: View {
    let title: String?
    let tone: RecipeApprovalSheet.Tone
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline).foregroundStyle(tone == .neutral ? Color.primary : ApprovalColors.color(tone))
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 1))
    }

    private var background: Color {
        tone == .neutral || tone == .accent ? Color(nsColor: .controlBackgroundColor) : ApprovalColors.color(tone).opacity(0.08)
    }

    private var border: Color {
        tone == .neutral || tone == .accent ? Color(nsColor: .separatorColor) : ApprovalColors.color(tone).opacity(0.45)
    }
}

struct ApprovalField: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .body)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
        }
    }
}

struct ApprovalSwitch: View {
    let title: String
    let explanation: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                if let explanation {
                    Text(explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

/// An AI tool's own words: shown as quoted text, never as Greenshot's.
struct AIWords: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(text)
                .italic()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }
}

/// A line of what the recipe does; uploads, programs and file access are marked (upstream `PopulateSteps`).
struct ApprovalStepLine: View {
    let line: RecipeDescriptionLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(line.risk == nil ? Color.accentColor : Color.orange)
                .frame(width: 14)
            Text(line.text)
                .fontWeight(line.risk != nil && !line.isDetail ? .semibold : .regular)
                .foregroundStyle(line.risk == nil ? Color.primary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.leading, line.isDetail ? 22 : 0)
    }

    private var symbol: String {
        switch line.risk {
        case .networkAccess: return "globe"
        case .externalCommand: return "terminal"
        case .fileSystemAccess: return "folder"
        case .custom: return "exclamationmark.triangle"
        case nil: return line.isDetail ? "arrow.turn.down.right" : "play.fill"
        }
    }
}
