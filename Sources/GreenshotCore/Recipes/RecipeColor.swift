// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Colors in recipe parameters (upstream `ColorTranslator.FromHtml`, `Color.FromName`): "#RGB", "#RRGGBB", "#AARRGGBB"
/// (alpha first, like .NET), "rgb(r, g, b)", "rgba(r, g, b, a)" with a from 0 to 255 (or 0 to 1 with a fraction),
/// and the .NET color names ("Black", "Transparent", "CornflowerBlue").
enum RecipeColor {
    static func parse(_ text: String) -> RGBAColor? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#") { return hex(String(trimmed.dropFirst())) }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("rgb"), let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") {
            return functional(String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]))
        }
        return LegacyKnownColors.argb(named: trimmed).map(argb)
    }

    private static func hex(_ digits: String) -> RGBAColor? {
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        switch digits.count {
        case 3:
            let red: UInt32 = ((value >> 8) & 0xF) * 0x11
            let green: UInt32 = ((value >> 4) & 0xF) * 0x11
            let blue: UInt32 = (value & 0xF) * 0x11
            var expanded: UInt32 = 0xFF00_0000
            expanded |= red << 16
            expanded |= green << 8
            expanded |= blue
            return argb(expanded)
        case 6:
            return argb(0xFF00_0000 | value)
        case 8:
            return argb(value)
        default:
            return nil
        }
    }

    private static func functional(_ inside: String) -> RGBAColor? {
        let parts = inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let numbers = parts.compactMap(Double.init)
        guard numbers.count == parts.count else { return nil }
        var alpha = 1.0
        if numbers.count == 4 {
            let raw = numbers[3]
            alpha = parts[3].contains(".") && raw <= 1 ? raw : raw / 255
        }
        func channel(_ value: Double) -> Double { min(max(value, 0), 255) / 255 }
        return RGBAColor(red: channel(numbers[0]), green: channel(numbers[1]), blue: channel(numbers[2]), alpha: min(max(alpha, 0), 1))
    }

    private static func argb(_ value: UInt32) -> RGBAColor {
        let alpha = Double((value >> 24) & 0xFF) / 255
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
