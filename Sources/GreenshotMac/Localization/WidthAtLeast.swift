// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A width for controls whose text is longer in other languages: `minimum` points, as many as the first subview's text
/// needs when that is more (up to `maximum`), never more than the row offers. Every subview gets that width; a measuring
/// subview (a hidden placeholder) comes first.
struct WidthAtLeast: Layout {
    var minimum: CGFloat
    var maximum: CGFloat = .infinity

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = width(for: proposal, subviews: subviews)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }

    private func width(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        let needed = subviews.first?.sizeThatFits(.unspecified).width ?? 0
        return min(max(minimum, min(needed, maximum)), proposal.width ?? .infinity)
    }
}

extension View {
    /// Instead of `.frame(maxWidth: minimum)` on a control with text (a popup button): `minimum` points like in English,
    /// more when its longest text needs more, up to `maximum`.
    func width(atLeast minimum: CGFloat, atMost maximum: CGFloat = .infinity) -> some View {
        WidthAtLeast(minimum: minimum, maximum: maximum) { self }
    }

    /// Instead of `.frame(width: minimum)` on a text field: `minimum` points like in English, wider (up to `maximum`) when
    /// the placeholder is longer, so it isn't cut.
    func width(atLeast minimum: CGFloat, atMost maximum: CGFloat, placeholder: LocalizedStringKey) -> some View {
        WidthAtLeast(minimum: minimum, maximum: maximum) {
            Text(placeholder).lineLimit(1).padding(.horizontal, 10).hidden()
            self
        }
    }
}
