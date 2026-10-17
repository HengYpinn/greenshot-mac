// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct EditorWindowZoomTests {
    @Test func zoomStepsFollowTheLadder() {
        #expect(EditorWindowZoom.zoomedIn(from: 1) == 2)
        #expect(EditorWindowZoom.zoomedOut(from: 1) == 0.75)
        #expect(EditorWindowZoom.zoomedIn(from: 0.25) == 0.5)
        #expect(EditorWindowZoom.zoomedOut(from: 2) == 1)
    }

    @Test func zoomStepsFromValuesBetweenSteps() {
        // After a pinch or a fit the magnification is anywhere.
        #expect(EditorWindowZoom.zoomedIn(from: 1.37) == 2)
        #expect(EditorWindowZoom.zoomedOut(from: 1.37) == 1)
        #expect(EditorWindowZoom.zoomedIn(from: 0.1) == 0.25)
        #expect(EditorWindowZoom.zoomedOut(from: 10) == 6)
    }

    @Test func nearlyEqualValuesCountAsTheStep() {
        #expect(EditorWindowZoom.zoomedIn(from: 0.6667) == 0.75)
        #expect(EditorWindowZoom.zoomedOut(from: 0.6667) == 0.5)
        #expect(EditorWindowZoom.zoomedIn(from: 1.001) == 2)
    }

    @Test func zoomStopsAtBothEnds() {
        #expect(EditorWindowZoom.zoomedIn(from: 6) == 6)
        #expect(EditorWindowZoom.zoomedOut(from: 0.25) == 0.25)
    }

    @Test func labelsAndPresets() {
        #expect(EditorWindowZoom.label(1) == "100%")
        #expect(EditorWindowZoom.label(2.0 / 3.0) == "66%")
        #expect(EditorWindowZoom.label(1.374) == "137%")
        #expect(abs(EditorWindowZoom.factor(percent: 66) - 2.0 / 3.0) < 1e-9)
        #expect(EditorWindowZoom.matches(0.6667, percent: 66))
        #expect(!EditorWindowZoom.matches(0.7, percent: 66))
        #expect(EditorWindowZoom.presetPercents.map(EditorWindowZoom.factor(percent:)) == EditorWindowZoom.ladder)
    }

    @Test func zoomingInGoesToTheVisiblePartOfTheSelection() {
        let viewport = CGRect(x: 100, y: 100, width: 400, height: 300)
        let image = CGSize(width: 2000, height: 1000)
        // Partly visible: the middle of the visible part.
        let selection = CGRect(x: 450, y: 350, width: 200, height: 200)
        #expect(EditorWindowZoom.anchor(viewport: viewport, imageSize: image, selection: selection, zoomingIn: true)
            == CGPoint(x: 475, y: 375))
        // Not visible at all: the middle of the view.
        let away = CGRect(x: 1500, y: 800, width: 10, height: 10)
        #expect(EditorWindowZoom.anchor(viewport: viewport, imageSize: image, selection: away, zoomingIn: true)
            == CGPoint(x: 300, y: 250))
    }

    @Test func zoomingInWithoutSelectionKeepsAFittingImageAtTheTopLeft() {
        // The image is narrower than the view but taller: left edge kept, vertical middle kept.
        let viewport = CGRect(x: -100, y: 200, width: 800, height: 400)
        let image = CGSize(width: 600, height: 1000)
        #expect(EditorWindowZoom.anchor(viewport: viewport, imageSize: image, selection: nil, zoomingIn: true)
            == CGPoint(x: 0, y: 400))
        // Fits both ways: the top left corner.
        #expect(EditorWindowZoom.anchor(viewport: CGRect(x: -50, y: -50, width: 800, height: 1200), imageSize: image,
                                        selection: nil, zoomingIn: true) == .zero)
    }

    @Test func zoomingOutKeepsTheMiddle() {
        let viewport = CGRect(x: 100, y: 100, width: 400, height: 300)
        let selection = CGRect(x: 450, y: 350, width: 200, height: 200)
        #expect(EditorWindowZoom.anchor(viewport: viewport, imageSize: CGSize(width: 2000, height: 1000), selection: selection,
                                        zoomingIn: false) == CGPoint(x: 300, y: 250))
    }
}

struct EditorWindowPlacementTests {
    let laptop = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let external = CGRect(x: 1440, y: 0, width: 2560, height: 1415)

    @Test func rememberedFrameOnAScreenIsUsed() {
        #expect(EditorWindowPlacement.isUsable(CGRect(x: 100, y: 100, width: 900, height: 600), screens: [laptop]))
        // Mostly off to the right, but 100 points of the title bar are still there.
        #expect(EditorWindowPlacement.isUsable(CGRect(x: 1340, y: 100, width: 900, height: 600), screens: [laptop]))
    }

    @Test func frameOnADisconnectedScreenIsReset() {
        let onExternal = CGRect(x: 2000, y: 300, width: 900, height: 600)
        #expect(EditorWindowPlacement.isUsable(onExternal, screens: [laptop, external]))
        #expect(!EditorWindowPlacement.isUsable(onExternal, screens: [laptop]))
        // Title bar above the top of the screen.
        #expect(!EditorWindowPlacement.isUsable(CGRect(x: 100, y: 900, width: 900, height: 600), screens: [laptop]))
        // Only 30 points of the title bar left.
        #expect(!EditorWindowPlacement.isUsable(CGRect(x: 1410, y: 100, width: 900, height: 600), screens: [laptop]))
        #expect(!EditorWindowPlacement.isUsable(.zero, screens: [laptop]))
    }

    @Test func screenOfAFrameIsTheOneShowingMostOfIt() {
        #expect(EditorWindowPlacement.screen(for: CGRect(x: 1300, y: 100, width: 900, height: 600), screens: [laptop, external]) == external)
        #expect(EditorWindowPlacement.screen(for: CGRect(x: 100, y: 100, width: 900, height: 600), screens: [laptop, external]) == laptop)
        #expect(EditorWindowPlacement.screen(for: CGRect(x: -5000, y: 0, width: 10, height: 10), screens: [laptop]) == nil)
    }

    @Test func fittedFrameIsContentPlusChromeWithinLimits() {
        let chrome = CGSize(width: 50, height: 120)
        // Small capture: upstream's minimum size.
        let small = EditorWindowPlacement.fittedFrame(contentSize: CGSize(width: 200, height: 100), chrome: chrome,
                                                      topLeft: CGPoint(x: 100, y: 800), screen: laptop)
        #expect(small == CGRect(x: 100, y: 270, width: 650, height: 530))
        // Middle size: exactly content plus chrome, top left kept.
        let middle = EditorWindowPlacement.fittedFrame(contentSize: CGSize(width: 800, height: 500), chrome: chrome,
                                                       topLeft: CGPoint(x: 100, y: 800), screen: laptop)
        #expect(middle == CGRect(x: 100, y: 180, width: 850, height: 620))
        // Larger than the screen: the screen.
        let large = EditorWindowPlacement.fittedFrame(contentSize: CGSize(width: 3000, height: 2000), chrome: chrome,
                                                      topLeft: CGPoint(x: 100, y: 800), screen: laptop)
        #expect(large == laptop)
    }

    @Test func fittedFrameMovesOntoTheScreenInsteadOfShrinking() {
        let frame = EditorWindowPlacement.fittedFrame(contentSize: CGSize(width: 800, height: 500), chrome: CGSize(width: 50, height: 120),
                                                      topLeft: CGPoint(x: 1000, y: 300), screen: laptop)
        #expect(frame == CGRect(x: 590, y: 0, width: 850, height: 620))
    }

    @Test func fittedFrameWithoutRememberedPlaceIsCentred() {
        let frame = EditorWindowPlacement.fittedFrame(contentSize: CGSize(width: 800, height: 500), chrome: CGSize(width: 50, height: 120),
                                                      topLeft: nil, screen: external)
        #expect(frame == CGRect(x: 1440 + 855, y: 397.5, width: 850, height: 620))
    }

    @Test func blankImageIsWhiteAtTheScreenScale() throws {
        let image = try #require(EditorWindowPlacement.blankImage(points: CGSize(width: 500, height: 500), scale: 2))
        #expect(image.width == 1000 && image.height == 1000)
        #expect(TestImage.pixel(image, 500, 500) == .white)
        #expect(TestImage.pixel(image, 0, 999) == .white)
    }
}

struct EditorWindowStatusTests {
    let home = URL(fileURLWithPath: NSHomeDirectory())

    @Test func savedFileNamesThePath() {
        let file = home.appendingPathComponent("Desktop/Screenshot.png")
        let message = EditorWindowStatus.message(for: .succeeded(fileURL: file), destination: "Save")
        #expect(message == .init(text: "Image saved to ~/Desktop/Screenshot.png."))
        #expect(EditorWindowStatus.line(message!, time: "10:00:00") == "10:00:00 - Image saved to ~/Desktop/Screenshot.png.")
    }

    @Test func otherExportsNameTheTargetOrTheDestination() {
        let link = URL(string: "https://jira.example.com/browse/DEV-1")
        #expect(EditorWindowStatus.message(for: .succeeded(link: link, target: "DEV-1"), destination: "Upload to Jira…")
            == .init(text: "Exported to: DEV-1"))
        #expect(EditorWindowStatus.message(for: .succeeded(), destination: "Upload to Box")
            == .init(text: "Exported to: Upload to Box"))
        #expect(EditorWindowStatus.message(for: .succeeded(), destination: "Print…") == .init(text: "Exported to: Print"))
    }

    @Test func failuresAreErrorsWithTheReason() {
        let message = EditorWindowStatus.message(for: .failed("The server did not answer."), destination: "Upload to Dropbox")
        #expect(message == .init(text: "An error occurred while exporting to Upload to Dropbox: The server did not answer.", isError: true))
        #expect(EditorWindowStatus.line(message!, time: "9:41:00 AM")
            == "9:41:00 AM - ⚠ An error occurred while exporting to Upload to Dropbox: The server did not answer.")
    }

    @Test func nothingToSayForDeclinedOrUnexplainedFailures() {
        #expect(EditorWindowStatus.message(for: .declined, destination: "Email") == nil)
        #expect(EditorWindowStatus.message(for: ExportResult(status: .failed), destination: "Email") == nil)
        #expect(EditorWindowStatus.message(for: .failed("  "), destination: "Email") == nil)
    }

    @Test func dimensionsAndNames() {
        #expect(EditorWindowStatus.dimensions(CGSize(width: 1280, height: 800)) == "1280 × 800 px")
        #expect(EditorWindowStatus.destinationName("Save as PDF…") == "Save as PDF")
        #expect(EditorWindowStatus.destinationName("Email...") == "Email")
        #expect(EditorWindowStatus.destinationName("Clipboard") == "Clipboard")
    }
}
