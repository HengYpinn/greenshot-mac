// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The turn of emoji, SVG and metafile elements in Greenshot for Windows files (`_rotationAngle` of upstream's
/// `VectorGraphicsContainer`) is kept. Upstream stores +90 per clockwise Rotate and -90 per counter-clockwise one
/// (`DrawableContainer.CalculateAngle`); no file saved upstream after a Rotate was at hand, so the sign follows the code.
struct LegacyImportRotationTests {
    private func element(_ typeName: String, _ content: LegacyElement.Content) -> LegacyElement {
        var element = LegacyElement(typeName: typeName, left: 10, top: 20, width: 40, height: 80)
        element.content = content
        return element
    }

    private func rotation(_ typeName: String, _ content: LegacyElement.Content) throws -> Int? {
        let annotation = try #require(GreenshotLegacyImport.annotation(element(typeName, content), scale: 1))
        return annotation.rotation
    }

    @Test func svgsKeepTheirTurn() throws {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"/>"#.utf8)
        #expect(try rotation("SvgContainer", .svg(svg, rotation: 90)) == 90)
        #expect(try rotation("SvgContainer", .svg(svg, rotation: -90)) == 270)
        #expect(try rotation("SvgContainer", .svg(svg, rotation: 180)) == 180)
        #expect(try rotation("SvgContainer", .svg(svg, rotation: -270)) == 90)
        #expect(try rotation("SvgContainer", .svg(svg, rotation: 0)) == nil)
    }

    @Test func emojiKeepTheirTurn() throws {
        #expect(try rotation("EmojiContainer", .emoji("🙂", rotation: 270)) == 270)
        #expect(try rotation("EmojiContainer", .emoji("🙂", rotation: -180)) == 180)
        #expect(try rotation("EmojiContainer", .emoji("🙂", rotation: 360)) == nil)
    }

    @Test func metafilePicturesKeepTheirTurnAndOtherPicturesHaveNone() throws {
        let png = try ImageExporter.data(for: TestImage.solid(width: 4, height: 8, .red), format: .png)
        #expect(try rotation("MetafileContainer", .picture(png, rotation: -90)) == 270)
        #expect(try rotation("ImageContainer", .picture(png, rotation: 0)) == nil)
    }

    @Test func theTurnedBoxStaysAndTheContentBoxIsUnturned() throws {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"/>"#.utf8)
        let annotation = try #require(GreenshotLegacyImport.annotation(element("SvgContainer", .svg(svg, rotation: 90)), scale: 1))
        #expect(annotation.bounds == CGRect(x: 10, y: 20, width: 40, height: 80))
        #expect(annotation.contentBounds == CGRect(x: -10, y: 40, width: 80, height: 40))
    }
}
