// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The colours last picked for elements, kept in `AppSettings.recentColors` (upstream `IEditorConfiguration.RecentColors`
/// and `ColorPickerWindow.AddToRecentColors`, `Greenshot.Editor/Views/ColorPickerWindow.xaml.cs`).
public enum RecentColors {
    /// How many are kept (upstream's 12 slots).
    public static let limit = 12

    /// `list` with `color` in front: newest first; a colour already in the list moves to the front; at most `limit`.
    /// Colours count as the same when they are at 8 bits per channel, the precision upstream keeps (a colour well's
    /// colour comes back with a little noise). A fully transparent colour is not kept: it is no colour to pick again.
    public static func remember(_ color: RGBAColor, in list: [RGBAColor]) -> [RGBAColor] {
        cleaned([color] + list)
    }

    /// `list` as `remember` keeps it: no colour twice (the first one stays), no transparent one, at most `limit`
    /// (settings can be edited by hand or come from a profile).
    public static func cleaned(_ list: [RGBAColor]) -> [RGBAColor] {
        var seen: Set<Key> = []
        var result: [RGBAColor] = []
        for color in list {
            let id = key(of: color)
            guard id.alpha > 0, seen.insert(id).inserted else { continue }
            result.append(color)
            if result.count == limit { break }
        }
        return result
    }

    /// The colour as `#RRGGBB`, with the alpha as a fourth byte (`#RRGGBBAA`) when it is not opaque: its name in the
    /// colour panel's palette.
    public static func name(of color: RGBAColor) -> String {
        let k = key(of: color)
        let rgb = String(format: "#%02X%02X%02X", k.red, k.green, k.blue)
        return k.alpha == 255 ? rgb : rgb + String(format: "%02X", k.alpha)
    }

    struct Key: Hashable {
        var red: Int, green: Int, blue: Int, alpha: Int
    }

    static func key(of color: RGBAColor) -> Key {
        Key(red: byte(color.red), green: byte(color.green), blue: byte(color.blue), alpha: byte(color.alpha))
    }

    /// A component as 0–255; values a file can hold outside 0–1 (or not finite) are clamped.
    static func byte(_ component: Double) -> Int {
        guard component.isFinite else { return 0 }
        return Int((min(max(component, 0), 1) * 255).rounded())
    }
}
