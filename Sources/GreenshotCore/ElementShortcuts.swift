// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The style properties the keyboard shortcuts change (upstream fields `LINE_COLOR`, `FILL_COLOR`, `LINE_THICKNESS`,
/// `SHADOW`).
public enum AnnotationStyleProperty: CaseIterable, Sendable {
    case lineColor, fillColor, lineWidth, shadow
}

extension AnnotationKind {
    /// Whether elements of this kind have `property`: the ones the property bar offers for it (upstream `HasField`, so
    /// a colour shortcut leaves elements without that field alone).
    public func has(_ property: AnnotationStyleProperty) -> Bool {
        switch property {
        case .lineColor:
            return [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .counter, .speechBubble, .cutMark, .tornEdge].contains(self)
        case .fillColor:
            return [.rectangle, .ellipse, .text, .counter, .highlight, .speechBubble, .cutMark, .tornEdge].contains(self)
        case .lineWidth:
            return [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .speechBubble, .counter, .cutMark, .tornEdge]
                .contains(self)
        case .shadow:
            // Every kind offers a shadow but SVG and pointer elements, which have no fields upstream
            // (`SvgContainer`, `CursorContainer`).
            return self != .svg && self != .cursor
        }
    }
}

extension AnnotationKind {
    /// The kinds that have `property`: the property bar shows its control for them.
    public static func kinds(with property: AnnotationStyleProperty) -> Set<AnnotationKind> {
        Set(allCases.filter { $0.has(property) })
    }

    /// The elements with cut edges: edge style, teeth and range, new random edges, the cut edge settings and Apply to the
    /// image (upstream `CutMarkContainer`, `TornEdgeContainer`).
    public static let cutEdgeKinds: Set<AnnotationKind> = [.cutMark, .tornEdge]
}

extension AnnotationStyle {
    /// Sets `property` to its value in `other`.
    public mutating func copy(_ property: AnnotationStyleProperty, from other: AnnotationStyle) {
        switch property {
        case .lineColor: lineColor = other.lineColor
        case .fillColor: fillColor = other.fillColor
        case .lineWidth: lineWidth = other.lineWidth
        case .shadow: shadow = other.shadow
        }
    }
}

/// The shortcuts that change the style of the selected elements (upstream `Surface.ProcessCmdKey`): Ctrl+0–9 the fill
/// colour, Ctrl+Shift+0–9 the line colour, Ctrl+plus and minus the line width (Shift: by 5), Ctrl+slash the shadow.
public enum ElementShortcuts {
    /// The colour of a digit key (upstream `SetSelectedElementColor` calls; the .NET colours Green and Gray are half
    /// bright). 0 is transparent for the fill and orange for the line.
    public static func color(digit: Int, line: Bool) -> RGBAColor? {
        switch digit {
        case 0: return line ? RGBAColor(red: 1, green: 165 / 255, blue: 0) : .clear
        case 1: return .red
        case 2: return RGBAColor(red: 0, green: 128 / 255, blue: 0)
        case 3: return .blue
        case 4: return RGBAColor(red: 0, green: 1, blue: 1)
        case 5: return RGBAColor(red: 1, green: 0, blue: 1)
        case 6: return .yellow
        case 7: return .black
        case 8: return RGBAColor(red: 128 / 255, green: 128 / 255, blue: 128 / 255)
        case 9: return .white
        default: return nil
        }
    }

    /// The largest line width the property bar offers (upstream `lineThicknessUpDown.Maximum`).
    public static let maximumLineWidth: Double = 100

    /// `width` changed by `step` points, never below 0 (upstream `IncreaseLineThickness`) nor above the maximum.
    public static func lineWidth(_ width: Double, changedBy step: Double) -> Double {
        min(max(width.rounded() + step, 0), maximumLineWidth)
    }
}
