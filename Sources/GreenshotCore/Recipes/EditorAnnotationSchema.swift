// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The fields of one annotation of an Annotation step, by its `Type`: the keys `RecipeAnnotationFactory` reads (upstream
/// docs section 4 and RecipeEditorWindow.xaml:1851-2540). The Annotation contract has no parameter list of its own.
public enum RecipeAnnotationSchema {
    /// Upstream's annotation types (docs "Supported Annotation Types").
    public static let types = ["Rectangle", "Ellipse", "Line", "Arrow", "Freehand", "Text", "SpeechBubble", "StepLabel", "Image",
                               "Icon", "Cursor", "Emoji", "Svg", "Blur", "Pixelize", "Highlight", "Magnify", "QRCode", "Barcode", "Crop"]
    public static let anchorsHorizontal = ["None", "Left", "Center", "Right"]
    public static let anchorsVertical = ["None", "Top", "Center", "Bottom"]
    /// Upstream `ArrowHeadCombination`.
    public static let arrowHeads = ["None", "StartPoint", "EndPoint", "Both"]
    /// Where a line or an arrow starts in its box (Mac `StartCorner`); it ends at the opposite corner.
    public static let startCorners = ["TopLeft", "TopRight", "BottomLeft", "BottomRight"]
    public static let tailDirections = ["BottomLeft", "BottomCenter", "BottomRight", "TopLeft", "TopCenter", "TopRight", "Left", "Right"]
    /// Upstream's cursor presets (docs "Standard Windows Cursor Presets").
    public static let cursorNames = ["Arrow", "AppStarting", "Cross", "Hand", "Help", "IBeam", "No", "SizeAll", "SizeNESW", "SizeNS",
                                     "SizeNWSE", "SizeWE", "UpArrow", "Wait"]
    /// Upstream's `QrType` values (docs "Specifying the QR Code Type Contract").
    public static let qrTypes = ["Text", "WiFi", "BusinessCard", "Payment", "Email", "CalendarEvent", "Phone", "Sms", "Geo"]
    public static let barcodeFormats = ["QR_CODE", "AZTEC", "DATA_MATRIX", "PDF_417", "CODE_128", "CODE_39", "CODE_93", "EAN_13",
                                        "EAN_8", "UPC_A", "UPC_E", "CODABAR", "ITF", "MSI", "PLESSEY"]

    private static func field(_ name: String, _ kind: RecipeEditorFieldKind, _ help: String = "", label: String? = nil,
                              default value: JSONValue? = nil) -> RecipeEditorField {
        RecipeEditorField(name: name, label: label ?? RecipeParameterForm.label(for: name), help: help, kind: kind, defaultValue: value)
    }

    /// Where it goes: anchors, offsets, absolute position, size, margins.
    public static let placement: [RecipeEditorField] = [
        field("HorizontalAnchor", .choice(anchorsHorizontal), "Left, Center or Right of the capture; None: Left/OffsetX", label: "H-Anchor"),
        field("VerticalAnchor", .choice(anchorsVertical), "Top, Center or Bottom of the capture; None: Top/OffsetY", label: "V-Anchor"),
        field("OffsetX", .integer, "Moves it right (points; expressions like ${payload.width - 60} work)", label: "Offset X / Left"),
        field("OffsetY", .integer, "Moves it down (points)", label: "Offset Y / Top"),
        field("Width", .integer, "Width in points"),
        field("Height", .integer, "Height in points"),
        field("Margin", .integer, "Distance from the anchored edge (default 10); a QR code's quiet zone too (0-10)"),
        field("LockAspectRatio", .boolean, "Keep the picture's proportions when a size is given")
    ]

    static let line: [RecipeEditorField] = [
        field("LineThickness", .integer, "Line / border thickness", default: .number(2)),
        field("LineColor", .color, "Line color", default: .string("Red")),
        field("Shadow", .boolean, "Draw a shadow")
    ]

    static let startCorner = field("StartCorner", .choice(startCorners), "Where the line starts; it ends at the opposite corner",
                                   default: .string("TopLeft"))

    static let fill = [field("FillColor", .color, "Fill color (rgba(r,g,b,a) works)")]

    static let font: [RecipeEditorField] = [
        field("FontFamily", .text, "Font family (default: the system font)"),
        field("FontSize", .decimal, "Font size"),
        field("Bold", .boolean),
        field("Italic", .boolean)
    ]

    /// The fields of a type, placement first. Unknown types get the rectangle's.
    public static func fields(forType type: String) -> [RecipeEditorField] {
        let text = field("Text", .multilineText, "The text; ${…} expressions work")
        switch type.lowercased() {
        case "rectangle", "ellipse":
            return placement + line + fill
        case "line":
            return placement + [startCorner] + line
        case "arrow":
            return placement + [startCorner] + line
                + [field("ArrowHeads", .choice(arrowHeads), "Arrow heads", default: .string("EndPoint"))]
        case "freehand":
            return line + [field("Points", .text, "The path: \"x,y;x,y;…\" in points")]
        case "text":
            return placement + [text] + font
                + [field("TextAlign", .choice(["Left", "Center", "Right"]), "Text alignment"), field("FitToText", .boolean, "Size the box to the text")]
                + line + fill
        case "speechbubble":
            return placement + [text] + font
                + [field("TailDirection", .choice(tailDirections), "Where the tail points"), field("TailOffsetX", .integer),
                   field("TailOffsetY", .integer)] + line + fill
        case "steplabel":
            return placement + [field("Number", .integer, "Step number (the Mac numbers counters by their order)")]
                + [field("FillColor", .color), field("LineColor", .color), field("Shadow", .boolean)]
        case "image", "icon":
            return placement + [field("ImageData", .multilineText, "The picture, embedded as Base64", label: "Embedded picture"),
                                field("FilePath", .filePath, "Or a picture file (.png .jpg .bmp .ico)"), field("Shadow", .boolean)]
        case "cursor":
            return placement + [field("CursorName", .choice(cursorNames), "Pointer preset", default: .string("Arrow")),
                                field("ImageData", .multilineText, "Or an embedded pointer picture (Base64)", label: "Embedded picture"),
                                field("FilePath", .filePath, "Or a pointer file")]
        case "emoji":
            return placement + [field("Emoji", .text, "The emoji"), field("Size", .integer, "Size in points", default: .number(64))]
        case "svg":
            return placement + [field("Content", .multilineText, "Inline SVG XML", label: "Inline SVG"),
                                field("FilePath", .filePath, "Or an .svg file"), field("ImageData", .multilineText, "Or the SVG as Base64",
                                                                                       label: "Embedded SVG")]
        case "blur":
            return placement + [field("BlurRadius", .integer, "Blur radius", default: .number(10))]
        case "pixelize":
            return placement + [field("PixelSize", .integer, "Pixel size", default: .number(5))]
        case "highlight":
            return placement + [field("FillColor", .color, "Highlight color", default: .string("Yellow"))]
        case "magnify":
            return placement + [field("MagnificationFactor", .integer, "Magnification (e.g. 2, 3)", default: .number(2))]
        case "qrcode", "barcode":
            return placement + [field("Format", .choice(barcodeFormats), "Barcode format", default: .string("QR_CODE")),
                                field("QrType", .choice(qrTypes), "What the QR code holds", default: .string("Text")),
                                field("Size", .integer, "Size of a square code (points)"), field("ForeColor", .color, "Code color"),
                                field("BackColor", .color, "Background"), field("RoundedDots", .boolean, "Rounded dots")]
        case "crop":
            return placement
        default:
            return placement + line + fill
        }
    }

    /// The content fields of a QR type (upstream "selecting a category reveals the exact input fields").
    public static func qrFields(forType qrType: String) -> [RecipeEditorField] {
        switch qrType.lowercased() {
        case "wifi":
            return [field("WifiSsid", .text, label: "Network (SSID)"), field("WifiPassword", .text, label: "Password"),
                    field("WifiEncryption", .choice(["WPA", "WEP", "nopass"]), label: "Encryption")]
        case "businesscard":
            return [field("VcardFirstName", .text, label: "First name"), field("VcardLastName", .text, label: "Last name"),
                    field("VcardPhone", .text, label: "Phone"), field("VcardEmail", .text, label: "Email"),
                    field("VcardCompany", .text, label: "Company"), field("VcardUrl", .text, label: "Website")]
        case "payment":
            return [field("EpcName", .text, label: "Recipient"), field("EpcIban", .text, label: "IBAN"), field("EpcBic", .text, label: "BIC"),
                    field("EpcAmount", .text, label: "Amount (EUR)"), field("EpcReference", .text, label: "Reference"),
                    field("EpcMessage", .text, label: "Message")]
        case "email":
            return [field("EmailTo", .text, label: "To"), field("EmailSubject", .text, label: "Subject"),
                    field("EmailBody", .multilineText, label: "Body")]
        case "calendarevent":
            return [field("EventTitle", .text, label: "Title"), field("EventLocation", .text, label: "Location"),
                    field("EventStart", .text, label: "Start (yyyyMMddTHHmmss)"), field("EventEnd", .text, label: "End"),
                    field("EventDescription", .multilineText, label: "Description")]
        case "phone":
            return [field("PhoneNumber", .text, label: "Phone number")]
        case "sms":
            return [field("SmsNumber", .text, label: "Number"), field("SmsMessage", .multilineText, label: "Message")]
        case "geo":
            return [field("Latitude", .text), field("Longitude", .text)]
        default:
            return [field("Text", .multilineText, "Text or link")]
        }
    }

    /// Every key an annotation can have (lowercased): a node's own annotation parameters are not "other parameters".
    public static let knownKeys: Set<String> = {
        var keys: Set<String> = ["type", "tailx", "taily", "marginleft", "marginright", "margintop", "marginbottom", "left", "top",
                                 "right", "bottom"]
        for type in types { keys.formUnion(fields(forType: type).map { $0.name.lowercased() }) }
        for type in qrTypes { keys.formUnion(qrFields(forType: type).map { $0.name.lowercased() }) }
        return keys
    }()

    /// The annotations of an Annotation node: its `Annotations` list, or its own parameters as one annotation.
    public static func annotations(of node: RecipeNode) -> [JSONObject] {
        if let list = node.parameters["Annotations"]?.arrayValue { return list.compactMap(\.objectValue) }
        var own: JSONObject = [:]
        for member in node.parameters where knownKeys.contains(member.key.lowercased()) { own[member.key] = member.value }
        return own.isEmpty ? [] : [own]
    }

    /// The node with `annotations` as its `Annotations` list (its own annotation parameters move into the list).
    public static func setting(_ annotations: [JSONObject], in node: RecipeNode) -> RecipeNode {
        var changed = node
        if changed.parameters["Annotations"] == nil {
            for key in changed.parameters.keys where knownKeys.contains(key.lowercased()) { changed.parameters[key] = nil }
        }
        changed.parameters["Annotations"] = .array(annotations.map { .object($0) })
        return changed
    }

    /// A short line for the list of annotations: "Text: Captured: ${now}", "QRCode: WiFi".
    public static func summary(_ annotation: JSONObject) -> String {
        let type = annotation.string("Type") ?? "Rectangle"
        if let text = annotation.string("Text"), !text.isEmpty { return "\(type): \(text.prefix(40))" }
        if recipeEquals(type, "QRCode"), let qr = annotation.string("QrType") { return "\(type): \(qr)" }
        if let emoji = annotation.string("Emoji") { return "\(type): \(emoji)" }
        if let cursor = annotation.string("CursorName") { return "\(type): \(cursor)" }
        return type
    }
}
