// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

extension Capture {
    /// The picture the editor opens: without the mouse pointer when the pointer comes as its own element.
    var editorImage: CGImage { pointer == nil ? image : (imageWithoutPointer ?? image) }
}

extension EditorWindowController {
    /// The property bar's buttons for cut marks and torn edges (Apply to the Image). Package E1 fills it in.
    func cutEdgeActionViews() -> [NSView] { [] }

    /// Adds the captured mouse pointer as an element, part of the opened capture (no undo step). Package E1 fills it in.
    func addCapturedPointer(of capture: Capture) {}
}
