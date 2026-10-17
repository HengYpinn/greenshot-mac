// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct MenuBarClickTests {
    @Test func showMenuClickKeepsTheMenuOnTheIcon() {
        #expect(MenuBarClick.clickShowsMenu(.showMenu))
        #expect(!MenuBarClick.clickShowsMenu(.captureRegion))
        // Even with a double-click action: the menu opens on the first click.
        #expect(MenuBarClick.decide(menuGesture: false, waiting: false, click: .showMenu, doubleClick: .openLastInFinder) == .showMenu)
    }

    @Test func rightAndControlClickAlwaysShowTheMenu() {
        for click in ClickAction.allCases {
            #expect(MenuBarClick.decide(menuGesture: true, waiting: false, click: click, doubleClick: .openSettings) == .showMenu)
            #expect(MenuBarClick.decide(menuGesture: true, waiting: true, click: click, doubleClick: .doNothing) == .showMenu)
        }
    }

    @Test func withoutDoubleClickActionTheClickRunsAtOnce() {
        #expect(MenuBarClick.decide(menuGesture: false, waiting: false, click: .captureRegion, doubleClick: .doNothing) == .run(.captureRegion))
        #expect(MenuBarClick.decide(menuGesture: false, waiting: false, click: .doNothing, doubleClick: .doNothing) == .run(.doNothing))
    }

    @Test func withDoubleClickActionTheFirstClickWaits() {
        #expect(MenuBarClick.decide(menuGesture: false, waiting: false, click: .captureRegion, doubleClick: .openLastInFinder)
                == .waitForSecondClick)
        #expect(MenuBarClick.decide(menuGesture: false, waiting: true, click: .captureRegion, doubleClick: .openLastInFinder)
                == .runDoubleClick(.openLastInFinder))
        // Upstream also waits when the click itself does nothing.
        #expect(MenuBarClick.decide(menuGesture: false, waiting: false, click: .doNothing, doubleClick: .openSettings) == .waitForSecondClick)
        #expect(MenuBarClick.decide(menuGesture: false, waiting: true, click: .doNothing, doubleClick: .openSettings) == .runDoubleClick(.openSettings))
    }

    @Test func clickActionsFollowUpstreamOrderAndDefaults() {
        #expect(ClickAction.allCases.count == 12)
        #expect(ClickAction.allCases.first == .doNothing && ClickAction.allCases.last == .openClipboardInEditor)
        let s = AppSettings()
        #expect(s.leftClickAction == .showMenu && s.doubleClickAction == .openLastInFinder)
        #expect(!s.hideMenuBarIcon && s.thumbnailPreview && s.maxMenuItemLength == 25 && s.theme == .system && !s.checkForUnstable)
    }
}

struct MenuBarTextTests {
    @Test func cutsLongWindowTitles() {
        #expect(MenuBarText.windowTitle(appName: "Safari", title: "Apple", maxLength: 25) == "Safari – Apple")
        let title = "Apple Developer Documentation – Swift"
        #expect(MenuBarText.windowTitle(appName: "Safari", title: title, maxLength: 25) == "Safari – Apple Developer Documenta…")
        // Exactly at the limit: unchanged.
        #expect(MenuBarText.windowTitle(appName: "Notes", title: "12345", maxLength: 5) == "Notes – 12345")
        // A cut that ends in a space doesn't keep it before the ellipsis.
        #expect(MenuBarText.windowTitle(appName: "Mail", title: "Inbox – All", maxLength: 6) == "Mail – Inbox…")
    }

    @Test func emptyTitlesAndOddLimits() {
        #expect(MenuBarText.windowTitle(appName: "Finder", title: "", maxLength: 25) == "Finder")
        #expect(MenuBarText.windowTitle(appName: "", title: "Untitled", maxLength: 25) == "Untitled")
        #expect(MenuBarText.windowTitle(appName: "App", title: "Hello", maxLength: 0) == "App – H…")
        // Emoji and accents count as one character each.
        #expect(MenuBarText.windowTitle(appName: "App", title: "👍🏽é👍🏽", maxLength: 2) == "App – 👍🏽é…")
    }
}

struct ScreenPositionTests {
    @Test func oneDisplayGetsNoWords() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(ScreenPosition.words(for: main, among: [main]).isEmpty)
        #expect(ScreenPosition.label(name: "Built-in", frame: main, among: [main]) == "Built-in")
    }

    @Test func sideBySideAndStacked() {
        let left = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let right = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        // The right one is taller: the left one touches only the top.
        #expect(ScreenPosition.words(for: left, among: [left, right]) == ["top", "left"])
        #expect(ScreenPosition.words(for: right, among: [left, right]) == ["right"])
        #expect(ScreenPosition.label(name: "LG", frame: right, among: [left, right]) == "LG (right)")

        // Quartz: y grows downwards, so the display above has the smaller y.
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let below = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(ScreenPosition.words(for: above, among: [above, below]) == ["top"])
        #expect(ScreenPosition.words(for: below, among: [above, below]) == ["bottom"])
    }

    @Test func middleOfThreeGetsNoWords() {
        let a = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let b = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let c = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        #expect(ScreenPosition.words(for: a, among: [a, b, c]) == ["left"])
        #expect(ScreenPosition.words(for: b, among: [a, b, c]).isEmpty)
        #expect(ScreenPosition.words(for: c, among: [a, b, c]) == ["right"])
    }
}

struct LastCaptureLocationTests {
    let output = URL(fileURLWithPath: "/Users/me/Desktop", isDirectory: true)

    @Test func theFileWhenItIsThere() {
        let found = LastCaptureLocation.resolve(lastSavedFile: "/Users/me/Pictures/a.png", outputFolder: output,
                                                fileExists: { _ in true }, directoryExists: { _ in true })
        #expect(found == .selectFile(URL(fileURLWithPath: "/Users/me/Pictures/a.png")))
    }

    @Test func itsFolderWhenTheFileIsGone() {
        let found = LastCaptureLocation.resolve(lastSavedFile: "/Users/me/Pictures/a.png", outputFolder: output,
                                                fileExists: { _ in false }, directoryExists: { $0 == "/Users/me/Pictures" })
        #expect(found == .openFolder(URL(fileURLWithPath: "/Users/me/Pictures", isDirectory: true)))
    }

    @Test func theOutputFolderOtherwise() {
        let gone = LastCaptureLocation.resolve(lastSavedFile: "/Volumes/USB/a.png", outputFolder: output,
                                               fileExists: { _ in false }, directoryExists: { $0 == "/Users/me/Desktop" })
        #expect(gone == .openFolder(output))
        let never = LastCaptureLocation.resolve(lastSavedFile: nil, outputFolder: output,
                                                fileExists: { _ in false }, directoryExists: { _ in true })
        #expect(never == .openFolder(output))
        let nothing = LastCaptureLocation.resolve(lastSavedFile: "/x/a.png", outputFolder: output,
                                                  fileExists: { _ in false }, directoryExists: { _ in false })
        #expect(nothing == nil)
    }
}

struct MenuBarThumbnailLayoutTests {
    @Test func scalesDownKeepingProportions() {
        #expect(MenuBarThumbnailLayout.size(for: CGSize(width: 1600, height: 1000)) == CGSize(width: 320, height: 200))
        #expect(MenuBarThumbnailLayout.size(for: CGSize(width: 3600, height: 400)) == CGSize(width: 360, height: 40))
        #expect(MenuBarThumbnailLayout.size(for: CGSize(width: 100, height: 50)) == CGSize(width: 100, height: 50))
        #expect(MenuBarThumbnailLayout.size(for: .zero) == .zero)
    }

    @Test func besideTheMenuInsideTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 320, height: 200)
        let menu = CGRect(x: 600, y: 300, width: 250, height: 500)
        // Right of the menu, centred on the mouse.
        #expect(MenuBarThumbnailLayout.frame(size: size, menuFrame: menu, mouse: CGPoint(x: 700, y: 500), screen: screen)
                == CGRect(x: 856, y: 400, width: 320, height: 200))
        // No room on the right: left of it.
        let edge = CGRect(x: 1200, y: 300, width: 230, height: 500)
        #expect(MenuBarThumbnailLayout.frame(size: size, menuFrame: edge, mouse: CGPoint(x: 1300, y: 500), screen: screen).minX == CGFloat(874))
        // Near the top of the screen: moved down to stay on it.
        #expect(MenuBarThumbnailLayout.frame(size: size, menuFrame: menu, mouse: CGPoint(x: 700, y: 880), screen: screen).maxY == CGFloat(900))
        // Unknown menu: beside the mouse.
        #expect(MenuBarThumbnailLayout.frame(size: size, menuFrame: nil, mouse: CGPoint(x: 100, y: 450), screen: screen).minX == CGFloat(118))
    }
}
