// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GreenshotCore

/// Upstream AiToolCapture / AiToolAccess.IsProcessExcluded and the Mac's setup texts.
@Suite struct AIToolCaptureTests {
    @Test func excludedNamesIgnoreCaseSpacesAndSuffixes() {
        let list = AIToolsSettings.defaultExcludedApplications
        #expect(AIToolExclusion.isExcluded(names: ["1Password"], excluded: list))
        #expect(AIToolExclusion.isExcluded(names: ["Proton Pass"], excluded: list))
        #expect(AIToolExclusion.isExcluded(names: ["keepassxc.app"], excluded: list))
        #expect(AIToolExclusion.isExcluded(names: [nil, "com.apple.keychainaccess"], excluded: ["Keychain Access", "keychainaccess"]))
        // A bundle identifier's last part
        #expect(AIToolExclusion.isExcluded(names: ["Some Name", "com.1password.1password"], excluded: list))
        #expect(!AIToolExclusion.isExcluded(names: ["Safari", "com.apple.Safari"], excluded: list))
        #expect(!AIToolExclusion.isExcluded(names: ["1Password"], excluded: []))
        #expect(AIToolExclusion.normalize(" KeePass.exe ") == "keepass")
    }

    /// SM-L3: older versions and helpers of a password manager, by name and by bundle identifier.
    @Test func excludedByNamePrefixAndBundleIdentifier() {
        let list = AIToolsSettings.defaultExcludedApplications
        #expect(AIToolExclusion.isExcluded(names: ["1Password 7"], excluded: list))
        #expect(AIToolExclusion.isExcluded(names: ["1Password Helper (Login)"], excluded: list))
        #expect(AIToolExclusion.isExcluded(names: ["Some Agent", "com.agilebits.onepassword7-helper"], excluded: list))
        #expect(AIToolExclusion.isExcluded(names: ["Vault", "com.bitwarden.desktop"], excluded: list))
        // A bundle prefix ends at a dot: com.agilebitsx isn't com.agilebits
        #expect(!AIToolExclusion.isExcluded(names: ["Other", "com.agilebitsx.app"], excluded: ["com.agilebits"]))
        #expect(!AIToolExclusion.isExcluded(names: ["Finder", "com.apple.finder"], excluded: list))
    }

    /// Fail closed: a black picture when the excluded windows can't be blacked out.
    @Test func blackPicture() throws {
        let black = try #require(AIToolExclusion.blackImage(width: 6, height: 4))
        #expect(black.width == 6)
        #expect(black.height == 4)
        #expect(pixel(black, x: 3, y: 2) == [0, 0, 0, 255])
    }

    @Test func redactionRectsAreClippedAndInPixels() {
        let rects = AIToolExclusion.redactionRects(windowFrames: [CGRect(x: 90, y: 40, width: 50, height: 20),
                                                                  CGRect(x: 500, y: 500, width: 10, height: 10)],
                                                   origin: CGPoint(x: 100, y: 30), scale: 2, pixelWidth: 200, pixelHeight: 100)
        #expect(rects == [CGRect(x: 0, y: 20, width: 80, height: 40)])
    }

    @Test func blackOutFillsTheRects() throws {
        let image = recipeTestImage(width: 10, height: 10)
        let blacked = try #require(AIToolExclusion.blackOut(image, rects: [CGRect(x: 0, y: 0, width: 5, height: 2)]))
        let topLeft = pixel(blacked, x: 1, y: 1)
        let bottomRight = pixel(blacked, x: 8, y: 8)
        #expect(topLeft == [0, 0, 0, 255])
        #expect(bottomRight != [0, 0, 0, 255])
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let originX = CGFloat(-x)
        let originY = CGFloat(y + 1 - image.height)
        context.draw(image, in: CGRect(x: originX, y: originY, width: CGFloat(image.width), height: CGFloat(image.height)))
        return data
    }

    @Test(arguments: [(3000, 2000, 1568, 1568, 1045), (1000, 4000, 1568, 392, 1568), (800, 600, 1568, 800, 600), (5000, 100, 0, 5000, 100)])
    func scaledToTheLongestSide(width: Int, height: Int, maxSize: Int, expectedWidth: Int, expectedHeight: Int) {
        let size = AIToolImage.scaledSize(width: width, height: height, maxSize: maxSize)
        #expect(size.width == expectedWidth)
        #expect(size.height == expectedHeight)
    }

    @Test func encodesPNGOfTheScaledSize() throws {
        let encoded = try #require(AIToolImage.encodePNG(recipeTestImage(width: 40, height: 20), maxSize: 10))
        #expect(encoded.width == 10)
        #expect(encoded.height == 5)
        let source = try #require(CGImageSourceCreateWithData(encoded.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 10)
    }

    @Test func regions() throws {
        let region = try #require(AIToolRegion(text: " 10, -20 ,300,200"))
        #expect(region.rect == CGRect(x: 10, y: -20, width: 300, height: 200))
        #expect(AIToolRegion(text: "1,2,0,4") == nil)
        #expect(AIToolRegion(text: "1,2,3") == nil)
        #expect(AIToolRegion(text: "a,b,c,d") == nil)
        #expect(AIToolRegion.text(of: [0, 10, 800, 600]) == "0,10,800,600")
    }

    @Test func ocrLinesInPixels() {
        let lines = AIToolImage.ocrLines([RecognizedLine(text: "Hello", bounds: CGRect(x: 4, y: 8, width: 40, height: 12), words: [])])
        let first = lines.arrayValue?.first?.objectValue
        #expect(first?.string("text") == "Hello")
        #expect(first?.int("y") == 8)
        #expect(first?.int("width") == 40)
    }

    @Test func setupSnippetsQuoteThePath() {
        let path = "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-mcp"
        #expect(AIToolSetupClient.claudeCode.snippet(serverPath: path) == "claude mcp add --scope user greenshot -- '\(path)'")
        #expect(AIToolSetupClient.shellQuoted("it's") == "'it'\\''s'")
        let json = AIToolSetupClient.claudeDesktop.snippet(serverPath: path)
        let parsed = try? JSONValue.parse(json)
        #expect(parsed?.objectValue?["mcpServers"]?.objectValue?["greenshot"]?.objectValue?.string("command") == path)
        let vsCode = try? JSONValue.parse(AIToolSetupClient.vsCode.snippet(serverPath: path))
        #expect(vsCode?.objectValue?["servers"]?.objectValue?["greenshot"]?.objectValue?.string("type") == "stdio")
        for client in AIToolSetupClient.allCases { #expect(!client.instructions.isEmpty) }
    }

    @Test func approvedRecipeLines() {
        var details = RecipeDetails()
        details.approvedAt = Date(timeIntervalSince1970: 1_792_238_400)
        details.isApprovalCurrent = true
        details.proposedBy = "Claude"
        details.triggers = [RecipeTriggerDescription(key: "0:Hotkey", label: "Hotkey (on)"),
                            RecipeTriggerDescription(key: "1:AiTool", label: "AI tool x (off, not approved)")]
        let row = AIToolApprovedRecipe(recipeId: "r", name: "Region to Jira", isExtension: false, details: details)
        #expect(row.subtitle == "approved 2026-10-17 · written by Claude · 1 trigger off")
        #expect(row.needsAttention)
        let unapproved = AIToolApprovedRecipe(recipeId: "e", name: "Border", isExtension: true, details: nil)
        #expect(unapproved.title == "Automatic step: Border")
        #expect(unapproved.subtitle == "not approved")
    }
}
