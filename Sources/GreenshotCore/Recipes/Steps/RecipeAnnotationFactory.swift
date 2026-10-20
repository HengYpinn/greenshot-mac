// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The parameters of one annotation, read like upstream's `GetString`/`GetInt`/`GetBool`/`GetColor`: a missing or
/// null value (or one that doesn't convert) gives the default.
struct AnnotationParameters {
    let object: JSONObject

    init(_ object: JSONObject) {
        self.object = object
    }

    func value(_ key: String) -> JSONValue? {
        guard let value = object[key], !value.isNull else { return nil }
        return value
    }

    /// Upstream `ContainsKey`: the key is there, whatever its value.
    func has(_ key: String) -> Bool { object[key] != nil }
    func string(_ key: String) -> String? { value(key)?.asString }
    func text(_ key: String) -> String? {
        guard let text = string(key), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    func int(_ key: String, _ fallback: Int) -> Int { value(key)?.asInt ?? fallback }
    func double(_ key: String, _ fallback: Double) -> Double { value(key)?.asDouble ?? fallback }
    func bool(_ key: String, _ fallback: Bool) -> Bool { value(key)?.asBool ?? fallback }
    func color(_ key: String, _ fallback: RGBAColor) -> RGBAColor { text(key).flatMap(RecipeColor.parse) ?? fallback }
    /// `Width`/`Height`: only a number above 0 counts.
    func positive(_ key: String) -> Double? {
        guard let number = value(key)?.asInt, number > 0 else { return nil }
        return Double(number)
    }
}

/// Upstream `AnnotationStep.CreateDrawable` with the built-in drawable factories (`RegisterBuiltInDrawables`) and the
/// Zxing plug-in's `QRCode`/`Barcode`, onto the Mac's elements. Geometry in the parameters is in points (upstream's
/// pixels at 96 DPI, decision D2); the elements are in image pixels.
struct RecipeAnnotationFactory {
    /// The capture's size in pixels and its pixels per point.
    let imageSize: CGSize
    let scale: CGFloat

    enum Made {
        /// An element to add.
        case element(Annotation)
        /// `Crop`: the image is cut to this box (pixels) once the node's other elements are added.
        case crop(CGRect)
        /// Nothing to add, and why (logged).
        case skipped(String)
    }

    /// An element before it is placed: its kind, style and content, its own size in points, and whether it keeps its
    /// aspect ratio when a size is given (upstream `ScaleOptions.Rational`).
    struct Draft {
        var element: Annotation
        var size: CGSize = .zero
        var rational = false
        /// QR codes and barcodes are sized by their factory, like upstream's `CreateQrDrawable`.
        var sized = false
    }

    /// The surface in points.
    var surface: CGSize {
        let pixelsPerPoint = scale > 0 ? scale : 1
        return CGSize(width: imageSize.width / pixelsPerPoint, height: imageSize.height / pixelsPerPoint)
    }

    /// The element of one annotation's (evaluated) parameters. `cursor` is the pointer picture of a `Cursor` annotation
    /// (looked up by the step, at one pixel per point). An unknown type, or a picture that can't be read where upstream's
    /// factory gives no element, becomes a rectangle like upstream.
    func make(_ p: AnnotationParameters, cursor: (image: CGImage, hotSpot: CGPoint)? = nil) -> Made {
        let type = p.text("Type")?.trimmingCharacters(in: .whitespaces) ?? "Rectangle"
        if recipeEquals(type, "Crop") {
            return .crop(pixels(frame(Draft(element: Annotation(kind: .rectangle, start: .zero, end: .zero)), p)))
        }
        if recipeEquals(type, "Freehand") {
            return .element(freehand(p))
        }
        if recipeEquals(type, "Cursor"), cursor == nil, p.text("ImageData") == nil, p.text("FilePath") == nil {
            return .skipped("the pointer picture '\(p.text("CursorName") ?? "Arrow")' is not available")
        }
        let draft: Draft
        do {
            draft = try self.draft(type, p, cursor: cursor) ?? shape(.rectangle, p)
        } catch {
            return .skipped(error.localizedDescription)
        }
        var element = draft.element
        let box = pixels(frame(draft, p))
        element.start = box.origin
        element.end = CGPoint(x: box.maxX, y: box.maxY)
        if element.kind == .speechBubble {
            element.tail = tail(of: box, p)
        }
        if element.kind == .line || element.kind == .arrow {
            (element.start, element.end) = Self.ends(of: box, startCorner: p.text("StartCorner"))
        }
        return .element(element)
    }

    /// A line's ends in its box: from `StartCorner` (TopLeft, TopRight, BottomLeft, BottomRight; a Mac addition, upstream
    /// lines always go from the top left) to the opposite corner.
    static func ends(of box: CGRect, startCorner: String?) -> (start: CGPoint, end: CGPoint) {
        let corner = startCorner?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let right = corner.hasSuffix("right")
        let bottom = corner.hasPrefix("bottom")
        return (CGPoint(x: right ? box.maxX : box.minX, y: bottom ? box.maxY : box.minY),
                CGPoint(x: right ? box.minX : box.maxX, y: bottom ? box.minY : box.maxY))
    }

    private struct PictureError: LocalizedError {
        let errorDescription: String?
    }

    /// The draft of a type, nil for a type this factory doesn't know (or that gives no element, upstream `null`).
    private func draft(_ type: String, _ p: AnnotationParameters, cursor: (image: CGImage, hotSpot: CGPoint)?) throws -> Draft? {
        switch type.lowercased() {
        case "rectangle": return shape(.rectangle, p)
        case "ellipse": return shape(.ellipse, p)
        case "line": return line(.line, p)
        case "arrow": return line(.arrow, p)
        case "text": return text(p)
        case "speechbubble": return speechBubble(p)
        case "steplabel": return stepLabel(p)
        case "image": return try picture(p, kind: .image, data: p.text("ImageData"))
        case "icon": return try picture(p, kind: .image, data: nil)
        case "cursor": return try pointer(p, cursor)
        case "emoji": return emoji(p)
        case "svg": return svg(p)
        case "blur", "pixelize": return obfuscate(p, blur: recipeEquals(type, "Blur"))
        case "highlight", "magnify": return highlight(p, magnify: recipeEquals(type, "Magnify"))
        case "qrcode", "barcode": return barcode(p)
        default:
            log.warn("Unknown drawable type '\(type)'. Defaulting to a rectangle.")
            return nil
        }
    }

    // MARK: Element types

    private func shape(_ kind: AnnotationKind, _ p: AnnotationParameters) -> Draft {
        var style = AnnotationStyle.defaults(for: kind)
        style.lineWidth = Double(p.int("LineThickness", 2))
        style.lineColor = p.color("LineColor", .red)
        style.fillColor = p.color("FillColor", .clear)
        style.shadow = p.bool("Shadow", true)
        return Draft(element: Annotation(kind: kind, start: .zero, end: .zero, style: style))
    }

    private func line(_ kind: AnnotationKind, _ p: AnnotationParameters) -> Draft {
        var style = AnnotationStyle.defaults(for: kind)
        style.lineWidth = Double(p.int("LineThickness", 2))
        style.lineColor = p.color("LineColor", .red)
        style.shadow = p.bool("Shadow", true)
        if kind == .arrow {
            style.arrowHeads = Self.arrowHeads(p.text("ArrowHeads")) ?? .end
        }
        return Draft(element: Annotation(kind: kind, start: .zero, end: .zero, style: style))
    }

    /// Upstream `ArrowHeadCombination` (NONE, START_POINT, END_POINT, BOTH) by name or number.
    static func arrowHeads(_ text: String?) -> ArrowHeads? {
        guard let text else { return nil }
        let name = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "_", with: "")
        switch name {
        case "none", "0": return ArrowHeads.none
        case "startpoint", "start", "1": return .start
        case "endpoint", "end", "2": return .end
        case "both", "3": return .both
        default: return nil
        }
    }

    /// Upstream `CreateFreehand`: the path of `Points` ("x,y;x,y" or "x y|x y", points), where it is drawn; upstream
    /// doesn't move a path when it places the element, so neither anchors nor offsets apply.
    private func freehand(_ p: AnnotationParameters) -> Annotation {
        var style = AnnotationStyle.defaults(for: .freehand)
        style.lineWidth = Double(p.int("LineThickness", 2))
        style.lineColor = p.color("LineColor", .red)
        style.shadow = p.bool("Shadow", false)
        var points: [CGPoint] = []
        for pair in (p.string("Points") ?? "").split(whereSeparator: { $0 == ";" || $0 == "|" }) {
            let coordinates = pair.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }
            guard coordinates.count == 2 else { continue }
            points.append(CGPoint(x: CGFloat(coordinates[0]) * scale, y: CGFloat(coordinates[1]) * scale))
        }
        let first = points.first ?? .zero
        return Annotation(kind: .freehand, start: first, end: points.last ?? first, points: points, style: style)
    }

    private func text(_ p: AnnotationParameters) -> Draft {
        var style = AnnotationStyle.defaults(for: .text)
        style.fontFamily = p.text("FontFamily") ?? ""
        style.fontSize = p.double("FontSize", 12)
        style.bold = p.bool("Bold", false)
        style.italic = p.bool("Italic", false)
        style.lineColor = p.color("LineColor", .red)
        style.fillColor = p.color("FillColor", .clear)
        style.lineWidth = Double(p.int("LineThickness", 0))
        style.shadow = p.bool("Shadow", true)
        switch p.text("TextAlign")?.lowercased() {
        case "left": style.horizontalAlignment = .left
        case "right": style.horizontalAlignment = .right
        default: style.horizontalAlignment = .center
        }
        let text = p.string("Text") ?? ""
        var draft = Draft(element: Annotation(kind: .text, start: .zero, end: .zero, text: text, style: style))
        // Upstream `FitToText` unless a width is given: the box the text needs (measured at one pixel per point).
        if p.bool("FitToText", true) && !p.has("Width") && !text.isEmpty {
            draft.size = AnnotationRenderer.textBoxSize(text, style: style, scale: 1, maxWidth: 100_000)
        }
        return draft
    }

    private func speechBubble(_ p: AnnotationParameters) -> Draft {
        var style = AnnotationStyle.defaults(for: .speechBubble)
        style.fontFamily = p.text("FontFamily") ?? ""
        style.fontSize = p.double("FontSize", 14)
        style.bold = p.bool("Bold", true)
        style.lineColor = p.color("LineColor", .blue)
        style.fillColor = p.color("FillColor", .white)
        style.lineWidth = Double(p.int("LineThickness", 2))
        style.shadow = p.bool("Shadow", false)
        return Draft(element: Annotation(kind: .speechBubble, start: .zero, end: .zero, text: p.string("Text") ?? "", style: style))
    }

    /// Upstream `ApplySpeechbubbleTail`: `TailX`/`TailY`, or a `TailDirection` with `TailOffsetX`/`TailOffsetY` (points).
    private func tail(of box: CGRect, _ p: AnnotationParameters) -> CGPoint {
        let points = CGRect(x: box.minX / scale, y: box.minY / scale, width: box.width / scale, height: box.height / scale)
        var tip: CGPoint
        if p.has("TailX") && p.has("TailY") {
            tip = CGPoint(x: p.int("TailX", Int(points.minX) - 20), y: p.int("TailY", Int(points.maxY) + 25))
        } else {
            switch p.text("TailDirection")?.lowercased() ?? "bottomleft" {
            case "bottomright": tip = CGPoint(x: points.maxX + 15, y: points.maxY + 25)
            case "bottomcenter": tip = CGPoint(x: points.midX, y: points.maxY + 25)
            case "topleft": tip = CGPoint(x: points.minX - 15, y: points.minY - 25)
            case "topright": tip = CGPoint(x: points.maxX + 15, y: points.minY - 25)
            case "topcenter": tip = CGPoint(x: points.midX, y: points.minY - 25)
            case "left": tip = CGPoint(x: points.minX - 25, y: points.midY)
            case "right": tip = CGPoint(x: points.maxX + 25, y: points.midY)
            default: tip = CGPoint(x: points.minX - 15, y: points.maxY + 25)
            }
            tip.x += CGFloat(p.int("TailOffsetX", 0))
            tip.y += CGFloat(p.int("TailOffsetY", 0))
        }
        return CGPoint(x: tip.x * scale, y: tip.y * scale)
    }

    /// Upstream `CreateStepLabel`: a counter (30 × 30 points, upstream `StepLabelContainer`). The Mac numbers counters
    /// by their order, so `Number` isn't used.
    private func stepLabel(_ p: AnnotationParameters) -> Draft {
        var style = AnnotationStyle.defaults(for: .counter)
        style.fillColor = p.color("FillColor", .darkRed)
        style.lineColor = p.color("LineColor", .white)
        style.shadow = p.bool("Shadow", false)
        return Draft(element: Annotation(kind: .counter, start: .zero, end: .zero, style: style), size: CGSize(width: 30, height: 30),
                     rational: true)
    }

    /// Upstream `CreateImage` (`ImageData` base64, else `FilePath`) and `CreateIcon` (`FilePath`): an image element at
    /// the picture's own size; an SVG file becomes an SVG element.
    private func picture(_ p: AnnotationParameters, kind: AnnotationKind, data base64: String?) throws -> Draft {
        var content: ElementPicture?
        if let base64 {
            guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                throw PictureError(errorDescription: "the embedded picture is not valid Base64")
            }
            content = ElementPictures.content(of: data)
        }
        if content == nil, let path = p.text("FilePath") {
            content = ElementPictures.content(of: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        var element: Annotation?
        switch content {
        case .picture(let image, let pictureScale):
            element = Annotation.picture(image, pictureScale: pictureScale, at: .zero, documentScale: scale)
        case .svg(let data):
            element = Annotation.svg(data, at: .zero, documentScale: scale)
        case nil:
            throw PictureError(errorDescription: "the picture could not be read")
        }
        guard var element else { throw PictureError(errorDescription: "the picture could not be stored") }
        element.style = .defaults(for: element.kind)
        element.style.shadow = p.bool("Shadow", false)
        return Draft(element: element, size: points(element.bounds.size), rational: element.kind == .svg)
    }

    /// Upstream `CreateCursor`: `ImageData` (base64), else the `CursorName` preset (`cursor`), else `FilePath`, else the
    /// arrow (`cursor`).
    private func pointer(_ p: AnnotationParameters, _ cursor: (image: CGImage, hotSpot: CGPoint)?) throws -> Draft {
        var picture: (image: CGImage, scale: CGFloat)?
        if let base64 = p.text("ImageData") {
            guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                throw PictureError(errorDescription: "the embedded pointer is not valid Base64")
            }
            picture = ElementPictures.load(data: data)
        } else if let cursor, p.text("CursorName") != nil || p.text("FilePath") == nil {
            picture = (cursor.image, 1)
        } else if let path = p.text("FilePath") {
            picture = ElementPictures.load(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        guard let picture, let data = try? ImageExporter.data(for: picture.image, format: .png, scale: picture.scale) else {
            throw PictureError(errorDescription: "the pointer picture could not be read")
        }
        let size = CGSize(width: CGFloat(picture.image.width) / picture.scale, height: CGFloat(picture.image.height) / picture.scale)
        return Draft(element: Annotation(kind: .cursor, start: .zero, end: .zero, imageData: data), size: size)
    }

    private func emoji(_ p: AnnotationParameters) -> Draft {
        let size = CGFloat(p.int("Size", 64))
        let element = Annotation(kind: .emoji, start: .zero, end: .zero, text: p.text("Emoji") ?? "\u{1F44D}")
        return Draft(element: element, size: CGSize(width: size, height: size), rational: true)
    }

    /// Upstream `CreateSvg`: `ImageData` (base64), else `FilePath`, else `Content` (the SVG text); nil (a rectangle,
    /// like upstream) when there is none this Mac can draw.
    private func svg(_ p: AnnotationParameters) -> Draft? {
        var data: Data?
        if let base64 = p.text("ImageData") {
            data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
        }
        if data == nil, let path = p.text("FilePath") {
            data = ElementSvg.data(ofFile: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        if data == nil, let content = p.text("Content") {
            data = Data(content.utf8)
        }
        guard let data, let element = Annotation.svg(data, at: .zero, documentScale: scale) else {
            log.warn("The SVG of an annotation could not be read. Defaulting to a rectangle.")
            return nil
        }
        return Draft(element: element, size: points(element.bounds.size), rational: true)
    }

    private func obfuscate(_ p: AnnotationParameters, blur: Bool) -> Draft {
        var style = AnnotationStyle.defaults(for: .obfuscate)
        if blur {
            style.obfuscateMode = .blur
            style.blurRadius = Double(max(p.int("BlurRadius", 10), 0))
        } else {
            style.obfuscateMode = .pixelate
            style.pixelSize = Double(max(p.int("PixelSize", 5), 1))
        }
        return Draft(element: Annotation(kind: .obfuscate, start: .zero, end: .zero, style: style))
    }

    private func highlight(_ p: AnnotationParameters, magnify: Bool) -> Draft {
        var style = AnnotationStyle.defaults(for: .highlight)
        if magnify {
            style.highlightMode = .magnify
            style.magnification = Double(max(p.int("MagnificationFactor", 2), 1))
        } else {
            style.highlightMode = .text
            style.fillColor = p.color("FillColor", .yellow)
        }
        return Draft(element: Annotation(kind: .highlight, start: .zero, end: .zero, style: style))
    }

    // MARK: QR codes and barcodes

    /// Upstream Zxing `CreateQrDrawable`: the code's content from `QrType` and its fields, `Format`, the colors, the
    /// margin, and its size: `Size`, else `Width`/`Height` (a matrix code stays square), else 160 × 160 (matrix) or
    /// 250 × 80 points.
    private func barcode(_ p: AnnotationParameters) -> Draft {
        var spec = BarcodeSpec()
        spec.symbology = Self.symbology(p.text("Format")) ?? .qrCode
        spec.qrType = Self.qrType(p.text("QrType"))
        func field(_ key: String) -> String { String((p.string(key) ?? "").prefix(BarcodeSpec.maxFieldLength)) }
        spec.text = field("Text")
        if spec.text.isEmpty && (spec.qrType == .text || spec.symbology != .qrCode) {
            spec.text = "https://getgreenshot.org"
        }
        spec.wifiSSID = field("WifiSsid")
        spec.wifiPassword = field("WifiPassword")
        switch p.text("WifiEncryption")?.lowercased() {
        case "wep": spec.wifiEncryption = .wep
        case "nopass": spec.wifiEncryption = .unencrypted
        default: spec.wifiEncryption = .wpa
        }
        spec.vCardFirstName = field("VcardFirstName")
        spec.vCardLastName = field("VcardLastName")
        spec.vCardPhone = field("VcardPhone")
        spec.vCardEmail = field("VcardEmail")
        spec.vCardCompany = field("VcardCompany")
        spec.vCardURL = field("VcardUrl")
        spec.epcName = field("EpcName")
        spec.epcIBAN = field("EpcIban")
        spec.epcBIC = field("EpcBic")
        spec.epcAmount = field("EpcAmount")
        spec.epcReference = field("EpcReference")
        spec.epcMessage = field("EpcMessage")
        spec.emailTo = field("EmailTo")
        spec.emailSubject = field("EmailSubject")
        spec.emailBody = field("EmailBody")
        spec.eventTitle = field("EventTitle")
        spec.eventLocation = field("EventLocation")
        spec.eventStart = field("EventStart")
        spec.eventEnd = field("EventEnd")
        spec.eventDescription = field("EventDescription")
        spec.phoneNumber = field("PhoneNumber")
        spec.smsNumber = field("SmsNumber")
        spec.smsMessage = field("SmsMessage")
        spec.latitude = field("Latitude")
        spec.longitude = field("Longitude")
        spec.foreground = p.color("ForeColor", .black)
        spec.background = p.color("BackColor", .white)
        spec.roundedDots = p.bool("RoundedDots", false)
        spec.margin = min(max(p.int("Margin", 1), BarcodeSpec.marginRange.lowerBound), BarcodeSpec.marginRange.upperBound)
        var element = Annotation(kind: .barcode, start: .zero, end: .zero)
        element.barcode = spec
        return Draft(element: element, size: Self.barcodeSize(p, matrix: spec.symbology.is2D), sized: true)
    }

    static func barcodeSize(_ p: AnnotationParameters, matrix: Bool) -> CGSize {
        let size = Double(p.int("Size", 0))
        if size > 0 { return CGSize(width: size, height: size) }
        let width = p.positive("Width")
        let height = p.positive("Height")
        if width != nil || height != nil {
            if matrix {
                let side = min(width ?? .greatestFiniteMagnitude, height ?? .greatestFiniteMagnitude)
                return CGSize(width: side, height: side)
            }
            return CGSize(width: width ?? 250, height: height ?? 80)
        }
        return matrix ? CGSize(width: 160, height: 160) : CGSize(width: 250, height: 80)
    }

    /// ZXing's format names ("QR_CODE", "CODE_128", ...), any case, with or without the underscores.
    static func symbology(_ name: String?) -> BarcodeSymbology? {
        guard let name else { return nil }
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        let names: [String: BarcodeSymbology] = ["qrcode": .qrCode, "qr": .qrCode, "aztec": .aztec, "datamatrix": .dataMatrix,
                                                 "pdf417": .pdf417, "code128": .code128, "code39": .code39, "code93": .code93,
                                                 "ean13": .ean13, "ean8": .ean8, "upca": .upcA, "upce": .upcE, "codabar": .codabar,
                                                 "itf": .itf, "msi": .msi, "plessey": .plessey]
        return names[key]
    }

    /// Upstream's `QrType` names onto the Mac's (Text and Link are both text).
    static func qrType(_ name: String?) -> QRPayloadType {
        switch name?.lowercased() {
        case "wifi": return .wifi
        case "businesscard": return .vCard
        case "payment": return .epcTransfer
        case "email": return .email
        case "calendarevent": return .calendarEvent
        case "phone": return .phone
        case "sms": return .sms
        case "geo": return .geo
        default: return .text
        }
    }

    // MARK: Placement

    private func points(_ size: CGSize) -> CGSize {
        let pixelsPerPoint = scale > 0 ? scale : 1
        return CGSize(width: size.width / pixelsPerPoint, height: size.height / pixelsPerPoint)
    }

    private func pixels(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    /// Upstream `ApplyPositioning`, in points: the size (`Width`, `Height`, `Size`; `LockAspectRatio` or a type that keeps
    /// its aspect ratio), then the place: `HorizontalAnchor` Left/Center/Right with `Left`/`Right`/margins, the same
    /// vertically, plus `OffsetX`/`OffsetY`.
    func frame(_ draft: Draft, _ p: AnnotationParameters) -> CGRect {
        let size = draft.sized ? draft.size : sized(draft, p)
        let offsetX = Double(p.int("OffsetX", 0))
        let offsetY = Double(p.int("OffsetY", 0))
        let margin = p.int("Margin", 10)
        let x = Self.position(anchor: p.text("HorizontalAnchor"), start: "Left", end: "Right", p,
                              surface: Double(surface.width), length: Double(size.width),
                              margins: (Double(p.int("MarginLeft", margin)), Double(p.int("MarginRight", margin))))
        let y = Self.position(anchor: p.text("VerticalAnchor"), start: "Top", end: "Bottom", p,
                              surface: Double(surface.height), length: Double(size.height),
                              margins: (Double(p.int("MarginTop", margin)), Double(p.int("MarginBottom", margin))))
        return CGRect(x: x + offsetX, y: y + offsetY, width: Double(size.width), height: Double(size.height))
    }

    private func sized(_ draft: Draft, _ p: AnnotationParameters) -> CGSize {
        let size = Double(p.int("Size", 0))
        let explicitWidth = p.positive("Width") ?? (size > 0 ? size : 0)
        let explicitHeight = p.positive("Height") ?? (size > 0 ? size : 0)
        var width = Double(draft.size.width)
        var height = Double(draft.size.height)
        guard p.bool("LockAspectRatio", false) || draft.rational else {
            if explicitWidth > 0 { width = explicitWidth }
            if explicitHeight > 0 { height = explicitHeight }
            return CGSize(width: width, height: height)
        }
        let ratio = width > 0 && height > 0 ? width / height : 1
        if explicitWidth > 0 && explicitHeight <= 0 {
            return CGSize(width: explicitWidth, height: max(1, (explicitWidth / ratio).rounded(.toNearestOrEven)))
        }
        if explicitHeight > 0 && explicitWidth <= 0 {
            return CGSize(width: max(1, (explicitHeight * ratio).rounded(.toNearestOrEven)), height: explicitHeight)
        }
        guard explicitWidth > 0 && explicitHeight > 0 else { return CGSize(width: width, height: height) }
        if abs(ratio - 1) < 0.001 {
            let side = size > 0 ? size : min(explicitWidth, explicitHeight)
            return CGSize(width: side, height: side)
        }
        if explicitWidth / explicitHeight > ratio {
            return CGSize(width: max(1, (explicitHeight * ratio).rounded(.toNearestOrEven)), height: explicitHeight)
        }
        return CGSize(width: explicitWidth, height: max(1, (explicitWidth / ratio).rounded(.toNearestOrEven)))
    }

    /// One axis of upstream `ApplyPositioning` (without the offset): `start`/`end` are "Left"/"Right" or "Top"/"Bottom".
    static func position(anchor: String?, start: String, end: String, _ p: AnnotationParameters, surface: Double,
                         length: Double, margins: (start: Double, end: Double)) -> Double {
        let hasStart = p.has(start)
        let hasEnd = p.has(end)
        let startValue = Double(p.int(start, 0))
        let endValue = Double(p.int(end, 0))
        if let anchor, recipeEquals(anchor, end) {
            if start == "Left" {
                // Horizontally upstream prefers `Right`, then 0 when `Left` is given, else the margin.
                let distance = hasEnd ? endValue : (hasStart ? 0 : margins.end)
                return surface - length - distance
            }
            if hasEnd { return surface - length - endValue }
            if hasStart { return startValue }
            return surface - length - margins.end
        }
        if let anchor, recipeEquals(anchor, "Center") {
            return (surface - length) / 2
        }
        if hasStart { return startValue }
        if hasEnd { return surface - length - endValue }
        return anchor.map { recipeEquals($0, start) } == true ? margins.start : 0
    }
}

private let log = Log("Recipes")
