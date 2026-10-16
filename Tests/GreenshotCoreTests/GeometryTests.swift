// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Testing
@testable import GreenshotCore

struct GeometryTests {
    @Test func appKitToQuartz() {
        let rect = Geometry.quartzRect(fromAppKit: CGRect(x: 10, y: 20, width: 100, height: 50), primaryScreenHeight: 900)
        #expect(rect == CGRect(x: 10, y: 830, width: 100, height: 50))
        #expect(Geometry.quartzPoint(fromAppKit: CGPoint(x: 5, y: 900), primaryScreenHeight: 900) == CGPoint(x: 5, y: 0))
    }

    @Test func rectFromCornersInAnyOrder() {
        #expect(Geometry.rect(from: CGPoint(x: 30, y: 5), to: CGPoint(x: 10, y: 25)) == CGRect(x: 10, y: 5, width: 20, height: 20))
    }

    @Test func pixelRectCoversPartialPixels() {
        #expect(Geometry.pixelRect(for: CGRect(x: 0.5, y: 0.5, width: 10, height: 10), scale: 2) == CGRect(x: 1, y: 1, width: 20, height: 20))
        #expect(Geometry.pixelRect(for: CGRect(x: 0.3, y: 0, width: 1, height: 1), scale: 2) == CGRect(x: 0, y: 0, width: 3, height: 2))
    }

    @Test func squareAndSnap() {
        #expect(Geometry.squareEnd(from: .zero, to: CGPoint(x: -10, y: 4)) == CGPoint(x: -10, y: 10))
        let snapped = Geometry.snap45(from: .zero, to: CGPoint(x: 10, y: 1))
        #expect(abs(snapped.y) < 0.001)
        #expect(abs(snapped.x - (101 as CGFloat).squareRoot()) < 0.001)
    }

    @Test func distanceToSegment() {
        #expect(Geometry.distance(from: CGPoint(x: 5, y: 3), toSegment: .zero, CGPoint(x: 10, y: 0)) == 3)
        #expect(Geometry.distance(from: CGPoint(x: 13, y: 4), toSegment: .zero, CGPoint(x: 10, y: 0)) == 5)
    }
}

struct ScreenComposerTests {
    /// A 100 x 50 point Retina display: red on the left half, blue on the right.
    let retina = FrozenScreen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2,
                              image: TestImage.make(width: 200, height: 100) { x, _ in x < 100 ? .red : .blue })

    @Test func cropWithinOneDisplayKeepsItsScale() throws {
        let result = try #require(ScreenComposer.image(of: CGRect(x: 60, y: 10, width: 20, height: 20), from: [retina]))
        #expect(result.scale == 2)
        #expect(result.image.width == 40 && result.image.height == 40)
        #expect(TestImage.pixel(result.image, 0, 0) == .blue)
    }

    @Test func cropKeepsTopAndBottomTheRightWayRound() throws {
        let screen = FrozenScreen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 1,
                                  image: TestImage.make(width: 10, height: 10) { _, y in y < 5 ? .red : .blue })
        let result = try #require(ScreenComposer.image(of: CGRect(x: 0, y: 0, width: 10, height: 10), from: [screen]))
        #expect(TestImage.pixel(result.image, 5, 0) == .red)
        #expect(TestImage.pixel(result.image, 5, 9) == .blue)
    }

    @Test func regionAcrossTwoDisplaysIsJoinedAtTheHigherScale() throws {
        let left = FrozenScreen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1,
                                image: TestImage.solid(width: 100, height: 100, .red))
        let right = FrozenScreen(displayID: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100), scale: 2,
                                 image: TestImage.solid(width: 200, height: 200, .blue))
        let result = try #require(ScreenComposer.image(of: CGRect(x: 50, y: 0, width: 100, height: 100), from: [left, right]))
        #expect(result.scale == 2)
        #expect(result.image.width == 200 && result.image.height == 200)
        #expect(TestImage.pixel(result.image, 10, 10).isClose(to: .red))
        #expect(TestImage.pixel(result.image, 150, 10).isClose(to: .blue))
    }

    @Test func partsOutsideEveryDisplayAreTransparent() throws {
        let top = FrozenScreen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 10, height: 10), scale: 1,
                               image: TestImage.solid(width: 10, height: 10, .red))
        let offset = FrozenScreen(displayID: 2, frame: CGRect(x: 10, y: 5, width: 10, height: 10), scale: 1,
                                  image: TestImage.solid(width: 10, height: 10, .blue))
        let result = try #require(ScreenComposer.image(of: ScreenComposer.union(of: [top, offset]), from: [top, offset]))
        #expect(result.image.width == 20 && result.image.height == 15)
        #expect(TestImage.pixel(result.image, 15, 2).a == 0)
        #expect(TestImage.pixel(result.image, 15, 10).isClose(to: .blue))
        #expect(TestImage.pixel(result.image, 2, 2).isClose(to: .red))
    }

    @Test func regionOutsideAllDisplaysIsNil() {
        #expect(ScreenComposer.image(of: CGRect(x: 500, y: 500, width: 10, height: 10), from: [retina]) == nil)
    }
}
