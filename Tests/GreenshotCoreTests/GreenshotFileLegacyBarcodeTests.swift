// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// Barcode elements of Greenshot for Windows files (upstream `BarcodeContainer` with its `ZxingModel`): a barcode element
/// when the file says what it shows, else the picture.
struct GreenshotFileLegacyBarcodeTests {
    private func barcode(_ model: LegacyElement.LegacyBarcodeModel?, picture: Data? = nil, margin: Int? = nil) -> LegacyElement {
        var element = LegacyElement(typeName: "BarcodeContainer", left: 40, top: 30, width: 120, height: 60)
        element.content = .barcode(picture: picture, model: model, margin: margin)
        return element
    }

    @Test func aModelMakesABarcodeElement() throws {
        var model = LegacyElement.LegacyBarcodeModel()
        model.formatIndex = 4
        model.texts["RawText"] = "GREENSHOT-42"
        model.foreColor = LegacyColor(value: 0xFF33_6699, knownColor: 0, state: 2, name: nil)
        model.margin = 2
        let element = try #require(GreenshotLegacyImport.annotation(barcode(model, margin: 3), scale: 1))
        let spec = try #require(element.barcode)
        #expect(element.kind == .barcode)
        #expect(element.imageData == nil)
        #expect(element.bounds == CGRect(x: 40, y: 30, width: 120, height: 60))
        #expect(spec.symbology == .code128)
        #expect(spec.text == "GREENSHOT-42")
        // The container's quiet zone wins over the model's (upstream `BarcodeContainer.Margin`).
        #expect(spec.margin == 3)
        let blue: Double = 0x99 / 255.0
        #expect(abs(spec.foreground.blue - blue) < 0.001)
        #expect(spec.background == .white)
        #expect(!element.style.shadow)
    }

    @Test func aQRCodeKeepsItsTypeAndFields() throws {
        var model = LegacyElement.LegacyBarcodeModel()
        model.qrCategoryIndex = 1
        model.wifiEncryptionIndex = 2
        model.texts["WifiSsid"] = "Home"
        model.texts["WifiPassword"] = "secret"
        model.roundedDots = true
        model.margin = 4
        let element = try #require(GreenshotLegacyImport.annotation(barcode(model), scale: 2))
        let spec = try #require(element.barcode)
        #expect(spec.symbology == .qrCode)
        #expect(spec.qrType == .wifi)
        #expect(spec.wifiSSID == "Home")
        #expect(spec.wifiPassword == "secret")
        #expect(spec.wifiEncryption == .unencrypted)
        #expect(spec.roundedDots)
        #expect(spec.margin == 4)
        // Without RawText upstream draws its sample URL, so the text stays the sample.
        #expect(spec.text == BarcodeSpec().text)
        #expect(spec.vCardFirstName.isEmpty)
    }

    @Test func unknownIndexesAndMarginsAreLimited() throws {
        var model = LegacyElement.LegacyBarcodeModel()
        model.formatIndex = 99
        model.qrCategoryIndex = -1
        model.wifiEncryptionIndex = 7
        let spec = GreenshotLegacyImport.barcodeSpec(model, margin: 50)
        #expect(spec.symbology == .qrCode)
        #expect(spec.qrType == .text)
        #expect(spec.wifiEncryption == .wpa)
        #expect(spec.margin == 10)
        let unset = GreenshotLegacyImport.barcodeSpec(LegacyElement.LegacyBarcodeModel(), margin: nil)
        #expect(unset.margin == 1)
    }

    @Test func withoutAModelItIsThePicture() throws {
        let png = try ImageExporter.data(for: TestImage.solid(width: 4, height: 4, .black), format: .png)
        let element = try #require(GreenshotLegacyImport.annotation(barcode(nil, picture: png), scale: 1))
        #expect(element.kind == .image)
        #expect(element.barcode == nil)
        #expect(element.imageData == png)
        // Neither a model nor a picture: it can't be shown.
        let result = GreenshotLegacyImport.convert([barcode(nil)], scale: 1)
        #expect(result.elements.isEmpty)
        #expect(result.unreadable == ["picture"])
    }

    /// A BinaryFormatter stream with a BarcodeContainer whose `_model` is a ZxingModel, its auto properties stored as
    /// backing fields the way .NET writes them.
    @Test func theReaderFindsTheModelsBackingFields() throws {
        typealias S = NRBFTestStream
        var data = S.header()
        data.append(contentsOf: NRBFTestStream.bytes([12], S.int32(2),
                                                     S.string("Greenshot.Plugin.Zxing, Version=1.0.0.0")))
        data.append(contentsOf: NRBFTestStream.bytes([5], S.int32(1), S.string("System.Collections.Generic.List`1"),
                                                     S.int32(2), S.string("_items"), S.string("_size"), [5, 0, 8],
                                                     S.int32(2)))
        data.append(contentsOf: NRBFTestStream.bytes([9], S.int32(3), S.int32(1)))
        data.append(contentsOf: NRBFTestStream.bytes([16], S.int32(3), S.int32(1)))
        // The container (id 4): its box, _margin and _model.
        let containerMembers = ["left", "top", "width", "height", "_margin", "_model"]
        data.append(contentsOf: NRBFTestStream.bytes([5], S.int32(4),
                                                     S.string("Greenshot.Plugin.Zxing.Drawing.BarcodeContainer"),
                                                     S.int32(Int32(containerMembers.count))))
        for name in containerMembers { data.append(contentsOf: S.string(name)) }
        data.append(contentsOf: NRBFTestStream.bytes([0, 0, 0, 0, 0, 2], [8, 8, 8, 8, 8], S.int32(2)))
        for value: Int32 in [10, 20, 90, 90, 2] { data.append(contentsOf: S.int32(value)) }
        // The model (id 5), inline.
        let modelMembers = ["FormatIndex", "QrCategoryIndex", "RawText", "RoundedDots", "ForeColor"]
        data.append(contentsOf: NRBFTestStream.bytes([5], S.int32(5),
                                                     S.string("Greenshot.Plugin.Zxing.Drawing.ZxingModel"),
                                                     S.int32(Int32(modelMembers.count))))
        for name in modelMembers { data.append(contentsOf: S.string("<\(name)>k__BackingField")) }
        data.append(contentsOf: NRBFTestStream.bytes([0, 0, 1, 0, 3], [8, 8, 1], S.string("System.Drawing.Color"),
                                                     S.int32(2)))
        data.append(contentsOf: S.int32(1) + S.int32(0))
        data.append(contentsOf: NRBFTestStream.bytes([6], S.int32(6), S.string("https://example.org")))
        data.append(1)
        // ForeColor (id 7): an ARGB System.Drawing.Color.
        data.append(contentsOf: NRBFTestStream.bytes([4], S.int32(7), S.string("System.Drawing.Color"), S.int32(4),
                                                     S.string("name"), S.string("value"), S.string("knownColor"),
                                                     S.string("state"), [1, 0, 0, 0, 9, 7, 7]))
        data.append(10)
        let argb: UInt64 = 0xFF00_8000
        data.append(contentsOf: withUnsafeBytes(of: argb.littleEndian) { Array($0) })
        data.append(contentsOf: [0, 0, 2, 0])
        data.append(11)

        let elements = try GreenshotLegacyReader.elements(fromPayload: data)
        let element = try #require(elements.first)
        guard case .barcode(_, let model?, let margin) = element.content else {
            Issue.record("No barcode model: \(element.content)")
            return
        }
        #expect(margin == 2)
        #expect(model.formatIndex == 1)
        #expect(model.texts["RawText"] == "https://example.org")
        #expect(model.roundedDots)
        let annotation = try #require(GreenshotLegacyImport.annotation(element, scale: 1))
        let spec = try #require(annotation.barcode)
        #expect(spec.symbology == .aztec)
        #expect(spec.text == "https://example.org")
        let green: Double = 0x80 / 255.0
        #expect(abs(spec.foreground.green - green) < 0.001)
        #expect(annotation.bounds == CGRect(x: 10, y: 20, width: 90, height: 90))
    }
}
