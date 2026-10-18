// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// The colours last used for elements as a palette of the colour panel: "Greenshot Recent" under Color Palettes, in the
/// panel every colour well of the editor opens. The Mac form of the recent colours row of upstream's colour picker
/// (`ColorPickerWindow.xaml.cs`, 12 colours kept in `IEditorConfiguration.RecentColors`); the list is
/// `AppSettings.recentColors`, managed by `RecentColors`.
@MainActor
final class EditorRecentColors {
    static let shared = EditorRecentColors()

    /// The palette in the colour panel; not written to disk (the settings keep the colours).
    let list = NSColorList(name: String(localized: "Greenshot Recent"))
    private var settings: SettingsStore?
    private var attached = false
    /// The settings stores whose list this palette follows (a reload or an administrator's lock changes it).
    private var observed: Set<ObjectIdentifier> = []
    /// Colours of wells that may still change, per well.
    private var picks = RecentColorPicks()

    /// How long a colour well's colour has to stay before it counts as picked (seconds): the well reports every colour
    /// the mouse passes in the panel.
    private static let settleTime: TimeInterval = 1

    /// Fills the palette from `settings` and adds it to the colour panel (once); colours used from now on are kept there,
    /// and the palette follows changes of the list from elsewhere (a reload of the settings, a profile).
    func install(settings: SettingsStore) {
        self.settings = settings
        if observed.insert(ObjectIdentifier(settings)).inserted {
            settings.onChange(of: \.recentColors) { [weak self] _ in self?.rebuild() }
        }
        rebuild()
        guard !attached else { return }
        attached = true
        NSColorPanel.shared.attachColorList(list)
    }

    /// Keeps `color` as the newest recent colour (a dialog's OK, like upstream's `ApplyColor`).
    func remember(_ color: RGBAColor) {
        guard let settings else { return }
        let updated = RecentColors.remember(color, in: settings.value.recentColors)
        // An administrator may have locked the list: then the update is dropped and the palette shows the locked one.
        if updated != settings.value.recentColors { settings.update { $0.recentColors = updated } }
        rebuild()
    }

    /// Keeps `color` once `source` (a colour well) has stopped changing for a moment. Each well waits on its own, so a
    /// pick elsewhere in the meantime doesn't drop this one.
    func picked(_ color: RGBAColor, from source: AnyObject) {
        picks.pick(color, from: ObjectIdentifier(source), at: ProcessInfo.processInfo.systemUptime)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleTime))
            self?.rememberSettled()
        }
    }

    private func rememberSettled() {
        // A little early is fine: the sleep and the uptime are measured apart.
        let settled = picks.settled(at: ProcessInfo.processInfo.systemUptime, after: Self.settleTime * 0.95)
        for color in settled { remember(color) }
    }

    /// The palette from the settings, newest first.
    private func rebuild() {
        let colors = RecentColors.cleaned(settings?.value.recentColors ?? [])
        for key in list.allKeys { list.removeColor(withKey: key) }
        for (index, color) in colors.enumerated() {
            let shown = NSColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue),
                                alpha: CGFloat(color.alpha))
            list.insertColor(shown, key: RecentColors.name(of: color), at: index)
        }
    }
}
