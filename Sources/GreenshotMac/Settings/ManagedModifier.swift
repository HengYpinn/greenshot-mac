// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore
import SwiftUI

extension View {
    /// Marks a settings control whose value an administrator can force with a configuration profile: then it is
    /// disabled and shows a lock, "Set by your organisation" (package ADMIN fills this in). Pass every setting the
    /// control writes, e.g. `.managed(\.outputFormat)`, `.managed(\.printing.grayscale, \.printing.monochrome)`.
    func managed(_ keyPaths: PartialKeyPath<AppSettings>...) -> some View { self }
}
