// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The About window: upstream `Greenshot/Views/AboutWindow.xaml(.cs)` with the credits of `AppAboutCredits` and its
/// "Self-Service" button. Keys like upstream: S opens Self-Service, E its System section, L or I its Files and Log;
/// Esc and Return close. The credit of the translation in use comes from its language pack (`about_translation`); a
/// language with machine translations for the texts its pack doesn't have says so below it (docs/translations.md).
/// (Upstream's animated logo and edition badges have no counterpart here.)
struct AboutView: View {
    var openSelfService: (SelfServiceSection?) -> Void
    var close: () -> Void

    static let textWidth: CGFloat = 360

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().frame(width: 96, height: 96)
            Text(AppInfo.name).font(.title2.weight(.semibold))
            Text("Version \(UpdateChecker.currentVersion) (\(AppAboutCredits.versionDetail))").foregroundStyle(.secondary)
                .textSelection(.enabled)
            CreditsText().frame(width: Self.textWidth, height: CreditsText.height(width: Self.textWidth))
            if let credit = L10nText.translationCredit() {
                Text(verbatim: credit).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(width: Self.textWidth)
            }
            if L10nText.hasMachineTranslations() {
                Text("Some texts in this language are machine translations.").font(.callout)
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: Self.textWidth)
            }
            HStack {
                Button("Self-Service…") { openSelfService(nil) }
                    .help("Check the setup, read the log and the system information (S)")
                Spacer()
                Button("OK", action: close).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: Self.textWidth + 48)
    }
}

/// The credits with their links, as the About panel showed them.
struct CreditsText: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(AppAboutCredits.make())
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {}

    /// The height of the credits at `width`.
    static func height(width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: AppAboutCredits.make())
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height) + 4
    }
}

@MainActor
final class AboutWindowController: DiagnosticsWindowController {
    private static var current: AboutWindowController?

    init(app: AppDelegate?) {
        var close: () -> Void = {}
        let view = AboutView(openSelfService: { section in app?.showSelfService(section: section) }, close: { close() })
        let height = CreditsText.height(width: AboutView.textWidth) + 260
        super.init(title: String(localized: "About \(AppInfo.name)"), content: view, size: NSSize(width: AboutView.textWidth + 48, height: height),
                   resizable: false)
        close = { [weak self] in self?.close() }
        keyWindow?.onKey = { event in
            guard let letter = KeyHandlingWindow.plainLetter(event) else { return false }
            switch letter {
            case "s": app?.showSelfService(section: nil)
            case "e": app?.showSelfService(section: .system)
            case "l", "i": app?.showSelfService(section: .files)
            default: return false
            }
            return true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    static func show(app: AppDelegate) {
        let controller = current ?? AboutWindowController(app: app)
        current = controller
        controller.present()
    }
}
