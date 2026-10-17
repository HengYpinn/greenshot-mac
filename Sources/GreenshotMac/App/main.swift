// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

MainActor.assumeIsolated {
    // The app's own NSApplication, so the exceptions AppKit catches reach the bug report (`GreenshotApplication`).
    let app = GreenshotApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
