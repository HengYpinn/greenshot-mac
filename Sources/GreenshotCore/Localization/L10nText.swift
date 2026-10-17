// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later
// Owned by L10N-INFRA after the wave 5 prep.

import Foundation

/// Texts of the language packs that aren't plain UI literals (upstream `Greenshot.Base/Languages/Texts.cs`). Filled in
/// by the L10N-INFRA package; until then every text stays English.
public enum L10nText {
    /// An English text that is also data (a built-in recipe's name): its upstream translation from the app's `Upstream`
    /// table, else the text itself (tests, helpers).
    public static func display(_ english: String, bundle: Bundle = .main) -> String { english }

    /// Upstream `about_translation` of the language in use, nil when there is none.
    public static func translationCredit(bundle: Bundle = .main) -> String? { nil }
}
