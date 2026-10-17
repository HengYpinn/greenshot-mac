// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct CaptureAnimationTests {
    @Test func quinticEaseOutStartsFastAndEndsSlowly() {
        #expect(CaptureAnimation.easeOutQuint(0) == 0)
        #expect(CaptureAnimation.easeOutQuint(1) == 1)
        #expect(CaptureAnimation.easeOutQuint(-1) == 0 && CaptureAnimation.easeOutQuint(2) == 1)
        #expect(CaptureAnimation.easeOutQuint(0.25) > 0.75)
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map(CaptureAnimation.easeOutQuint)
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func aMotionSlidesToItsTarget() {
        let start = Date(timeIntervalSince1970: 100)
        let motion = CaptureMotion(from: CGRect(x: 0, y: 0, width: 10, height: 10), to: CGRect(x: 100, y: 50, width: 30, height: 20),
                                   start: start, duration: CaptureAnimation.selectionDuration)
        #expect(motion.value(at: start) == motion.from)
        #expect(motion.value(at: start.addingTimeInterval(0.7)) == motion.to)
        #expect(motion.value(at: start.addingTimeInterval(5)) == motion.to)
        let middle = motion.value(at: start.addingTimeInterval(0.35))
        #expect(middle.minX > 90 && middle.minX < 100)
        #expect(!motion.isFinished(at: start.addingTimeInterval(0.69)) && motion.isFinished(at: start.addingTimeInterval(0.7)))
    }

    @Test func labelsFadeInAfterAQuarterSecond() {
        #expect(CaptureAnimation.labelsOpacity(after: 0) == 0)
        #expect(CaptureAnimation.labelsOpacity(after: 0.25) == 0)
        #expect(abs(CaptureAnimation.labelsOpacity(after: 0.4) - 0.5) < 0.001)
        #expect(CaptureAnimation.labelsOpacity(after: 0.55) == 1)
    }

    @Test func aShownPanelOnlyGrows() {
        #expect(CaptureAnimation.grownSize(nil, CGSize(width: 100, height: 40)) == CGSize(width: 100, height: 40))
        #expect(CaptureAnimation.grownSize(CGSize(width: 120, height: 30), CGSize(width: 100, height: 40)) == CGSize(width: 120, height: 40))
    }

    @Test func timings() {
        #expect(CaptureAnimation.panelMoveDuration == 0.35 && CaptureAnimation.panelFadeDuration == 0.15)
        #expect(CaptureAnimation.selectionSettleTime == 0.3)
        let half = CaptureAnimation.progress(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 0.15), duration: 0.3)
        #expect(abs(half - 0.5) < 0.000_001)
    }
}
