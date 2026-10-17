// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

MainActor.assumeIsolated {
    // The language of the texts, before the first text is looked up (L10N).
    LanguageStartup.apply()
    // --help, the command after the startup options and one running instance per user; quits when this start only
    // forwards its command or another copy runs already.
    AutomationStartup.run()
    // The app's own NSApplication, so the exceptions AppKit catches reach the bug report (`GreenshotApplication`).
    let app = GreenshotApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
