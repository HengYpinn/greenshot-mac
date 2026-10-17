// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Binds the arguments a caller passes (CLI, `greenshot://`, browser extension, AI tool) to the arguments a trigger
/// declares (upstream `CommandlineArgumentBinder`): only declared names, required/default, type conversion. Paths go
/// through `resolvePath` (AUT's security rules and working directory); a thrown error's description is the message.
public enum RecipeArgumentBinder {
    public static func bind(declared: [CommandlineArgument], supplied: [String: String], recipeName: String,
                            resolvePath: (String, ContractDataType) throws -> String) -> Result<[String: JSONValue], RecipeStepError> {
        rcoreStub()
    }
}
