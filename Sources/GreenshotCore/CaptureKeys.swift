// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

/// The letter keys of the capture screen: Z zoomer, M pointer, F fixed size, T text and the others.
public enum CaptureKeys {
    /// The letter a key press stands for: the letter it `typed` when that is a Latin letter (or [ or ]), so on French
    /// or German keyboards the key with the letter on it; else what the key types on the Latin layout macOS uses for
    /// shortcuts (`latin`), so the keys also work with a Russian, Greek, Hebrew or Arabic layout. Upstream reads the
    /// virtual key, which is a Latin letter on every layout.
    public static func letter(typed: String?, latin: () -> String?) -> String {
        let typed = typed?.lowercased() ?? ""
        if isLatin(typed) { return typed }
        return latin()?.lowercased() ?? typed
    }

    private static func isLatin(_ key: String) -> Bool {
        guard key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first else { return false }
        return ("a"..."z").contains(scalar) || scalar == "[" || scalar == "]"
    }
}
