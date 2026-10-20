// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// One element offered by the recipe editor's "Import Annotations" sheet (upstream `ImportableElementItem`).
public struct RecipeAnnotationImportItem: Sendable, Equatable, Identifiable {
    public var id: UUID
    /// "Rectangle", "Text", "QRCode"…
    public var type: String
    /// "Text: Hello", for the list.
    public var description: String
    /// "120 × 40 pt".
    public var dimensions: String
    /// The annotation's parameters without its picture.
    public var parameters: JSONObject
    /// A picture, SVG or pointer: its bytes and their file extension (".png", ".svg"); embedded or saved to a file.
    public var asset: Data?
    public var assetExtension: String

    public var canSaveAsFile: Bool { asset != nil }
}

/// How the pictures of imported elements are kept (upstream `AssetStorageMode`).
public enum RecipeAssetStorage: Sendable, Equatable {
    /// Base64 in the recipe (upstream "Embed (Base64)").
    case embed
    /// Files `{prefix}_{type}_{n}{ext}` in a folder (upstream "Save to File").
    case saveToFile(folder: URL, prefix: String)
}

/// Editor elements as recipe annotations: the inverse of `RecipeAnnotationFactory` (upstream
/// Helpers/EditorAnnotationImporter.cs `ConvertContainerToAnnotation`, `ProcessImport`). Positions are absolute (anchors
/// None, `OffsetX`/`OffsetY`) in points, like upstream's.
public enum RecipeAnnotationExport {
    /// The import items of a document's elements (image pixels, `scale` pixels per point), in order; elements a recipe
    /// can't make (cut marks, torn edges) are left out.
    public static func items(of annotations: [Annotation], scale: CGFloat) -> [RecipeAnnotationImportItem] {
        annotations.compactMap { item(of: $0, scale: scale) }
    }

    /// Sorted A–Z by type, then by description (upstream's "A-Z" toggle).
    public static func sortedAlphabetically(_ items: [RecipeAnnotationImportItem]) -> [RecipeAnnotationImportItem] {
        items.sorted {
            let byType = $0.type.localizedStandardCompare($1.type)
            return byType == .orderedSame ? $0.description.localizedStandardCompare($1.description) == .orderedAscending
                : byType == .orderedAscending
        }
    }

    public static func item(of annotation: Annotation, scale: CGFloat) -> RecipeAnnotationImportItem? {
        guard let parameters = parameters(of: annotation, scale: scale) else { return nil }
        var asset: Data?
        var assetExtension = ".png"
        switch annotation.kind {
        case .image, .cursor:
            asset = annotation.imageData
        case .svg:
            asset = annotation.imageData
            assetExtension = ".svg"
        default:
            break
        }
        let type = parameters.string("Type") ?? "Rectangle"
        let width = parameters.int("Width") ?? 0
        let height = parameters.int("Height") ?? 0
        return RecipeAnnotationImportItem(id: annotation.id, type: type, description: RecipeAnnotationSchema.summary(parameters),
                                          dimensions: "\(width) × \(height) pt", parameters: parameters, asset: asset,
                                          assetExtension: assetExtension)
    }

    /// The file name of the n-th saved picture (upstream `{safeBase}_{type}_{n}{ext}`, one counter for all).
    public static func assetFileName(prefix: String, type: String, index: Int, fileExtension: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>\0")
        let safe = (prefix.isEmpty ? "asset" : prefix).components(separatedBy: invalid).joined(separator: "_")
        return "\(safe)_\(type.lowercased())_\(index)\(fileExtension)"
    }

    /// The annotations to put in the step: embedded pictures, or `FilePath`s of the files `write` saves (upstream
    /// `ProcessImport`; a picture that can't be written stays embedded).
    public static func annotations(of items: [RecipeAnnotationImportItem], storage: RecipeAssetStorage,
                                   write: (Data, URL) throws -> Void) -> [JSONValue] {
        var counter = 1
        return items.map { item in
            var parameters = item.parameters
            if let asset = item.asset, case .saveToFile(let folder, let prefix) = storage {
                let url = folder.appendingPathComponent(assetFileName(prefix: prefix, type: item.type, index: counter,
                                                                      fileExtension: item.assetExtension))
                counter += 1
                do {
                    try write(asset, url)
                    parameters["FilePath"] = .string(url.path)
                    parameters["ImageData"] = nil
                    parameters["Content"] = nil
                } catch {
                    if item.assetExtension != ".svg" { parameters["ImageData"] = .string(asset.base64EncodedString()) }
                }
            }
            return .object(parameters)
        }
    }

    /// One element as annotation parameters; nil for kinds recipes don't have.
    public static func parameters(of annotation: Annotation, scale: CGFloat) -> JSONObject? {
        let pixelsPerPoint = scale > 0 ? scale : 1
        let box = annotation.kind == .freehand ? annotation.bounds : CGRect(
            x: min(annotation.start.x, annotation.end.x), y: min(annotation.start.y, annotation.end.y),
            width: abs(annotation.end.x - annotation.start.x), height: abs(annotation.end.y - annotation.start.y))
        func points(_ value: CGFloat) -> JSONValue { .number((Double(value / pixelsPerPoint)).rounded()) }
        let style = annotation.style
        var p: JSONObject = [:]
        func placement() {
            p["HorizontalAnchor"] = .string("None")
            p["VerticalAnchor"] = .string("None")
            p["OffsetX"] = points(box.minX)
            p["OffsetY"] = points(box.minY)
            p["Width"] = points(box.width)
            p["Height"] = points(box.height)
        }
        func lineStyle() {
            p["LineThickness"] = .number(style.lineWidth.rounded())
            p["LineColor"] = .string(format(style.lineColor))
            p["Shadow"] = .bool(style.shadow)
        }
        func font() {
            if !style.fontFamily.isEmpty { p["FontFamily"] = .string(style.fontFamily) }
            p["FontSize"] = .number(style.fontSize)
            p["Bold"] = .bool(style.bold)
            p["Italic"] = .bool(style.italic)
        }
        switch annotation.kind {
        case .rectangle, .ellipse:
            p["Type"] = .string(annotation.kind == .rectangle ? "Rectangle" : "Ellipse")
            placement()
            lineStyle()
            p["FillColor"] = .string(format(style.fillColor))
        case .line, .arrow:
            p["Type"] = .string(annotation.kind == .line ? "Line" : "Arrow")
            placement()
            // Upstream writes the box only (EditorAnnotationImporter makes negative sizes positive), so a line comes back
            // from the top left to the bottom right; the corner it starts at keeps its direction (Mac `StartCorner`).
            let vertical = annotation.start.y > annotation.end.y ? "Bottom" : "Top"
            let horizontal = annotation.start.x > annotation.end.x ? "Right" : "Left"
            if vertical + horizontal != "TopLeft" { p["StartCorner"] = .string(vertical + horizontal) }
            lineStyle()
            if annotation.kind == .arrow { p["ArrowHeads"] = .string(arrowHeads(style.arrowHeads)) }
        case .freehand:
            p["Type"] = .string("Freehand")
            lineStyle()
            let path = annotation.points.map { point -> String in
                let x = Int((Double(point.x / pixelsPerPoint)).rounded())
                let y = Int((Double(point.y / pixelsPerPoint)).rounded())
                return "\(x),\(y)"
            }
            p["Points"] = .string(path.joined(separator: ";"))
        case .text, .speechBubble:
            p["Type"] = .string(annotation.kind == .text ? "Text" : "SpeechBubble")
            placement()
            p["Text"] = .string(annotation.text)
            font()
            if annotation.kind == .text {
                p["TextAlign"] = .string(style.horizontalAlignment.rawValue.capitalized)
                p["FitToText"] = .bool(false)
            }
            lineStyle()
            p["FillColor"] = .string(format(style.fillColor))
            if annotation.kind == .speechBubble, let tail = annotation.tail {
                p["TailX"] = points(tail.x)
                p["TailY"] = points(tail.y)
            }
        case .counter:
            p["Type"] = .string("StepLabel")
            placement()
            p["FillColor"] = .string(format(style.fillColor))
            p["LineColor"] = .string(format(style.lineColor))
            p["Shadow"] = .bool(style.shadow)
        case .emoji:
            p["Type"] = .string("Emoji")
            placement()
            p["Emoji"] = .string(annotation.text)
            p["Size"] = points(min(box.width, box.height))
        case .obfuscate:
            placement()
            if style.obfuscateMode == .blur {
                p["Type"] = .string("Blur")
                p["BlurRadius"] = .number(style.blurRadius.rounded())
            } else {
                p["Type"] = .string("Pixelize")
                p["PixelSize"] = .number(style.pixelSize.rounded())
            }
        case .highlight:
            placement()
            if style.highlightMode == .magnify {
                p["Type"] = .string("Magnify")
                p["MagnificationFactor"] = .number(style.magnification.rounded())
            } else {
                p["Type"] = .string("Highlight")
                p["FillColor"] = .string(format(style.fillColor))
            }
        case .image:
            p["Type"] = .string("Image")
            placement()
            p["Shadow"] = .bool(style.shadow)
            if let data = annotation.imageData { p["ImageData"] = .string(data.base64EncodedString()) }
        case .cursor:
            p["Type"] = .string("Cursor")
            placement()
            if let data = annotation.imageData { p["ImageData"] = .string(data.base64EncodedString()) }
        case .svg:
            p["Type"] = .string("Svg")
            placement()
            if let data = annotation.imageData, let text = String(data: data, encoding: .utf8) { p["Content"] = .string(text) }
        case .barcode:
            guard let spec = annotation.barcode else { return nil }
            p["Type"] = .string(spec.symbology == .qrCode ? "QRCode" : "Barcode")
            placement()
            if spec.symbology.is2D { p["Size"] = points(min(box.width, box.height)) }
            for member in parameters(of: spec) { p[member.key] = member.value }
        case .cutMark, .tornEdge:
            return nil
        }
        return p
    }

    /// A barcode's content and look as annotation parameters (the inverse of the factory's `barcode`); only the fields of
    /// its QR type are written.
    public static func parameters(of spec: BarcodeSpec) -> JSONObject {
        var p: JSONObject = [:]
        p["Format"] = .string(formatName(spec.symbology))
        p["QrType"] = .string(qrTypeName(spec.qrType))
        func put(_ key: String, _ value: String) { p[key] = .string(value) }
        switch spec.symbology == .qrCode ? spec.qrType : .text {
        case .text:
            put("Text", spec.text)
        case .wifi:
            put("WifiSsid", spec.wifiSSID)
            put("WifiPassword", spec.wifiPassword)
            put("WifiEncryption", spec.wifiEncryption == .wep ? "WEP" : spec.wifiEncryption == .unencrypted ? "nopass" : "WPA")
        case .vCard:
            put("VcardFirstName", spec.vCardFirstName)
            put("VcardLastName", spec.vCardLastName)
            put("VcardPhone", spec.vCardPhone)
            put("VcardEmail", spec.vCardEmail)
            put("VcardCompany", spec.vCardCompany)
            put("VcardUrl", spec.vCardURL)
        case .epcTransfer:
            put("EpcName", spec.epcName)
            put("EpcIban", spec.epcIBAN)
            put("EpcBic", spec.epcBIC)
            put("EpcAmount", spec.epcAmount)
            put("EpcReference", spec.epcReference)
            put("EpcMessage", spec.epcMessage)
        case .email:
            put("EmailTo", spec.emailTo)
            put("EmailSubject", spec.emailSubject)
            put("EmailBody", spec.emailBody)
        case .calendarEvent:
            put("EventTitle", spec.eventTitle)
            put("EventLocation", spec.eventLocation)
            put("EventStart", spec.eventStart)
            put("EventEnd", spec.eventEnd)
            put("EventDescription", spec.eventDescription)
        case .phone:
            put("PhoneNumber", spec.phoneNumber)
        case .sms:
            put("SmsNumber", spec.smsNumber)
            put("SmsMessage", spec.smsMessage)
        case .geo:
            put("Latitude", spec.latitude)
            put("Longitude", spec.longitude)
        }
        p["ForeColor"] = .string(format(spec.foreground))
        p["BackColor"] = .string(format(spec.background))
        p["RoundedDots"] = .bool(spec.roundedDots)
        p["Margin"] = .number(Double(spec.margin))
        return p
    }

    /// The spec a QRCode/Barcode annotation describes (the factory's reading), for "Configure QR…".
    public static func spec(of parameters: JSONObject) -> BarcodeSpec {
        let factory = RecipeAnnotationFactory(imageSize: CGSize(width: 1000, height: 1000), scale: 1)
        var code = parameters
        let type = code.string("Type") ?? ""
        if !recipeEquals(type, "QRCode") && !recipeEquals(type, "Barcode") { code["Type"] = .string("QRCode") }
        if case .element(let element) = factory.make(AnnotationParameters(code)), let spec = element.barcode { return spec }
        return BarcodeSpec()
    }

    /// The parameters with `spec`'s content and look, the other QR types' fields removed.
    public static func applying(_ spec: BarcodeSpec, to parameters: JSONObject) -> JSONObject {
        var result = parameters
        let contentKeys = RecipeAnnotationSchema.qrTypes.flatMap { RecipeAnnotationSchema.qrFields(forType: $0).map(\.name) }
        for key in contentKeys { result[key] = nil }
        for member in self.parameters(of: spec) { result[member.key] = member.value }
        result["Type"] = .string(spec.symbology == .qrCode ? "QRCode" : "Barcode")
        return result
    }

    /// Upstream `FormatColor`: "transparent", "#RRGGBB" or "#AARRGGBB".
    public static func format(_ color: RGBAColor) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let alpha = byte(color.alpha)
        if alpha == 0 { return "transparent" }
        let rgb = String(format: "%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
        return alpha == 255 ? "#\(rgb)" : String(format: "#%02X", alpha) + rgb
    }

    static func arrowHeads(_ heads: ArrowHeads) -> String {
        switch heads {
        case .none: return "NONE"
        case .start: return "START_POINT"
        case .end: return "END_POINT"
        case .both: return "BOTH"
        }
    }

    static func qrTypeName(_ type: QRPayloadType) -> String {
        switch type {
        case .text: return "Text"
        case .wifi: return "WiFi"
        case .vCard: return "BusinessCard"
        case .epcTransfer: return "Payment"
        case .email: return "Email"
        case .calendarEvent: return "CalendarEvent"
        case .phone: return "Phone"
        case .sms: return "Sms"
        case .geo: return "Geo"
        }
    }

    static func formatName(_ symbology: BarcodeSymbology) -> String {
        switch symbology {
        case .qrCode: return "QR_CODE"
        case .aztec: return "AZTEC"
        case .dataMatrix: return "DATA_MATRIX"
        case .pdf417: return "PDF_417"
        case .code128: return "CODE_128"
        case .code39: return "CODE_39"
        case .code93: return "CODE_93"
        case .ean13: return "EAN_13"
        case .ean8: return "EAN_8"
        case .upcA: return "UPC_A"
        case .upcE: return "UPC_E"
        case .codabar: return "CODABAR"
        case .itf: return "ITF"
        case .msi: return "MSI"
        case .plessey: return "PLESSEY"
        }
    }
}
