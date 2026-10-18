// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Carbon.HIToolbox
import GreenshotCore
import SwiftUI

/// The Self-Service window: port of upstream `Greenshot/SelfService/Views/SelfServiceWindow.xaml(.cs)` and
/// `ViewModels/SelfServiceViewModel.cs`. A sidebar of sections with their problem counts, the section, a status line.
@MainActor
final class SelfServiceModel: ObservableObject {
    @Published private(set) var section: SelfServiceSection
    @Published var status = ""

    let system: SystemSectionModel
    let setup: SetupModel
    let files: FilesSectionModel
    let clipboard: ClipboardSectionModel
    let hotkeys: HotkeysSectionModel
    let integrity: IntegritySectionModel

    init(section: SelfServiceSection, system: SystemSectionModel, setup: SetupModel, files: FilesSectionModel,
         clipboard: ClipboardSectionModel, hotkeys: HotkeysSectionModel, integrity: IntegritySectionModel) {
        self.section = section
        self.system = system
        self.setup = setup
        self.files = files
        self.clipboard = clipboard
        self.hotkeys = hotkeys
        self.integrity = integrity
    }

    /// The live window: every section reads the app and the Mac.
    convenience init(section: SelfServiceSection, app: AppDelegate) {
        self.init(section: section, system: SystemSectionModel(), setup: SetupModel(app: app), files: FilesSectionModel(app: app),
                  clipboard: ClipboardSectionModel(), hotkeys: HotkeysSectionModel(app: app), integrity: IntegritySectionModel())
    }

    var appTitle: String {
        "\(AppInfo.name) \(UpdateChecker.currentVersion) (\(AppAboutCredits.architecture))"
    }

    /// Shows a section and reads it again (upstream `OnNavigatedTo`).
    func select(_ newSection: SelfServiceSection) {
        if newSection != section {
            if section == .clipboard { clipboard.stopMonitoring() }
            section = newSection
        }
        refresh(newSection)
    }

    func refresh(_ which: SelfServiceSection? = nil) {
        switch which ?? section {
        case .system: system.refresh()
        case .setup: setup.refresh()
        case .files: files.refresh()
        case .clipboard: clipboard.refresh()
        case .hotkeys: hotkeys.refresh()
        case .integrity: integrity.refresh()
        }
    }

    /// Everything at once, for the problem counts in the sidebar.
    func refreshAll() {
        SelfServiceSection.allCases.forEach(refresh)
    }

    func refreshFromKey() {
        refresh()
        status = "Refreshed!"
    }

    func close() {
        clipboard.stopMonitoring()
    }
}

struct SelfServiceView: View {
    @ObservedObject var model: SelfServiceModel

    var body: some View {
        HStack(spacing: 0) {
            SelfServiceSidebar(model: model, setup: model.setup, hotkeys: model.hotkeys, integrity: model.integrity)
                .frame(width: 220)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.section.title).font(.title2.weight(.semibold))
                        Text(model.section.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { model.refreshFromKey() }
                        .help("Read this section again (F5, ⌘R)")
                        .keyboardShortcut("r", modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider()
                ScrollView {
                    detail
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                Divider()
                HStack {
                    Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("Esc: Close  |  F5: Refresh  |  1–6: Sections").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .system: SystemSectionView(model: model.system, status: { model.status = $0 })
        case .setup: SetupSectionView(model: model.setup)
        case .files: FilesSectionView(model: model.files, status: { model.status = $0 })
        case .clipboard: ClipboardSectionView(model: model.clipboard, status: { model.status = $0 })
        case .hotkeys: HotkeysSectionView(model: model.hotkeys, status: { model.status = $0 })
        case .integrity: IntegritySectionView(model: model.integrity, status: { model.status = $0 })
        }
    }
}

/// The list of sections, with the number of problems of a section next to it (upstream's badges).
struct SelfServiceSidebar: View {
    @ObservedObject var model: SelfServiceModel
    @ObservedObject var setup: SetupModel
    @ObservedObject var hotkeys: HotkeysSectionModel
    @ObservedObject var integrity: IntegritySectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Self-Service").font(.headline)
                    Text(model.appTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.bottom, 12)
            Text("DIAGNOSTICS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 8)
            ForEach(SelfServiceSection.allCases, id: \.self) { section in
                row(section)
            }
            Spacer()
            Text("Press 1–6 to switch sections, F5 to refresh.").font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
    }

    private func badge(_ section: SelfServiceSection) -> Int {
        switch section {
        case .setup: return setup.problemCount
        case .hotkeys: return hotkeys.issueCount
        case .integrity: return integrity.problemCount
        default: return 0
        }
    }

    private func row(_ section: SelfServiceSection) -> some View {
        let selected = model.section == section
        let count = badge(section)
        return Button {
            model.select(section)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.symbol).frame(width: 18)
                // A long word (German "Tastenkombinationen") gets a little smaller instead of breaking in the middle.
                Text(section.title).lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                if count > 0 {
                    Text("\(count)").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

/// A row of label and value in a section (upstream's cards of label and value).
struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A titled box of a section.
struct SectionCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }
}

/// Monospaced, selectable text in a box (reports, the log at a glance).
struct ReportText: View {
    var text: String
    var height: CGFloat

    var body: some View {
        ScrollView {
            Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .frame(height: height)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor)))
    }
}

@MainActor
final class SelfServiceWindowController: DiagnosticsWindowController {
    let model: SelfServiceModel
    private static var shared: SelfServiceWindowController?

    init(model: SelfServiceModel) {
        self.model = model
        super.init(title: String(localized: "\(AppInfo.name) Self-Service"), content: SelfServiceView(model: model),
                   size: NSSize(width: 900, height: 640), resizable: true, autosaveName: "GreenshotSelfService")
        keyWindow?.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// Opens the window, or brings it to the front, on `section` when given (upstream `ShowSelfService`).
    static func show(section: SelfServiceSection?, app: AppDelegate) {
        let controller = shared ?? SelfServiceWindowController(model: SelfServiceModel(section: section ?? .system, app: app))
        shared = controller
        let wasOpen = controller.isOpen
        if let section { controller.model.select(section) }
        if !wasOpen { controller.model.refreshAll() }
        controller.present()
    }

    override func didClose() {
        model.close()
    }

    /// Back from System Settings: the checks again.
    override func didBecomeKey() {
        if model.section == .setup || model.section == .hotkeys { model.refresh() }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_F5 {
            model.refreshFromKey()
            return true
        }
        if let letter = KeyHandlingWindow.plainLetter(event), let section = SelfServiceSection(key: letter) {
            model.select(section)
            return true
        }
        return false
    }
}
