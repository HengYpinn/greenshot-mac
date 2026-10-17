// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

@inline(never)
func rcoreStub(_ function: StaticString = #function) -> Never {
    fatalError("RCORE: \(function) is implemented in wave 3, phase 2")
}
