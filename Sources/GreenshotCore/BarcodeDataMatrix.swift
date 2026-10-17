// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Data Matrix ECC 200 (upstream: ZXing's DataMatrixWriter). Filled in later in this branch.
enum DataMatrixEncoder {
    static func matrix(_ payload: String) throws -> BarcodeMatrix {
        throw BarcodeError.tooLong
    }

    static func regionSide(symbolSide: Int) -> Int { symbolSide - 2 }
}
