// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The codes of upstream's Insert QR / Barcode dialog, in the order of its format list
/// (`Greenshot.Plugin.Zxing/Views/ZxingEditorWindow.xaml.cs`, `InitializeDropdowns` and `MapFormatIndex`).
public enum BarcodeSymbology: String, Codable, CaseIterable, Sendable {
    case qrCode, aztec, dataMatrix, pdf417, code128, code39, code93, ean13, ean8, upcA, upcE, codabar, itf, msi, plessey

    /// QR, Aztec, Data Matrix and PDF-417 are matrix codes: drawn without distortion, resized keeping their aspect
    /// ratio (upstream `BarcodeContainer.Is2D`).
    public var is2D: Bool {
        switch self {
        case .qrCode, .aztec, .dataMatrix, .pdf417: return true
        case .code128, .code39, .code93, .ean13, .ean8, .upcA, .upcE, .codabar, .itf, .msi, .plessey: return false
        }
    }

    /// Upstream's `ZxingModel.FormatIndex`: the position in the format list.
    public var upstreamIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public init?(upstreamIndex: Int) {
        guard Self.allCases.indices.contains(upstreamIndex) else { return nil }
        self = Self.allCases[upstreamIndex]
    }
}

/// What a QR code holds (upstream `ZxingModel.QrCategoryIndex`, same order).
public enum QRPayloadType: String, Codable, CaseIterable, Sendable {
    case text, wifi, vCard, epcTransfer, email, calendarEvent, phone, sms, geo

    /// Upstream's `ZxingModel.QrCategoryIndex`.
    public var upstreamIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public init?(upstreamIndex: Int) {
        guard Self.allCases.indices.contains(upstreamIndex) else { return nil }
        self = Self.allCases[upstreamIndex]
    }
}

/// The security of a WiFi network (upstream `ZxingModel.WifiEncryptionIndex`: WPA/WPA2, WEP, unencrypted).
public enum WiFiEncryption: String, Codable, CaseIterable, Sendable {
    case wpa, wep, unencrypted
}

/// What a barcode element shows and how it looks: upstream's `ZxingModel`, which `BarcodeContainer` keeps in its `Tag`.
/// Like upstream it keeps the fields of every QR type, so the dialog shows them again after switching back.
public struct BarcodeSpec: Codable, Hashable, Sendable {
    public var symbology: BarcodeSymbology = .qrCode
    public var qrType: QRPayloadType = .text
    /// The text or URL of a QR code, and the value of every other code (upstream `RawText`; the dialog starts with
    /// upstream's sample URL).
    public var text = "https://getgreenshot.org"
    public var wifiSSID = ""
    public var wifiPassword = ""
    public var wifiEncryption: WiFiEncryption = .wpa
    public var vCardFirstName = ""
    public var vCardLastName = ""
    public var vCardPhone = ""
    public var vCardEmail = ""
    public var vCardCompany = ""
    public var vCardURL = ""
    public var epcName = ""
    public var epcIBAN = ""
    public var epcBIC = ""
    /// The amount in euros as typed (upstream's field starts at 10.00).
    public var epcAmount = "10.00"
    public var epcReference = ""
    public var epcMessage = ""
    public var emailTo = ""
    public var emailSubject = ""
    public var emailBody = ""
    public var eventTitle = ""
    public var eventLocation = ""
    /// As typed, in iCalendar form such as 20261017T090000Z (upstream "Start (UTC)").
    public var eventStart = ""
    public var eventEnd = ""
    public var eventDescription = ""
    public var phoneNumber = ""
    public var smsNumber = ""
    public var smsMessage = ""
    public var latitude = ""
    public var longitude = ""
    /// The dark modules (upstream `ForeColor`, black).
    public var foreground: RGBAColor = .black
    /// The light modules and the quiet zone (upstream `BackColor`, white).
    public var background: RGBAColor = .white
    /// Matrix codes drawn with round dots; the finder patterns of a QR code stay square (upstream `RoundedDots`).
    public var roundedDots = false
    /// The quiet zone in modules: on every side of a matrix code, left and right of a bar code (upstream `Margin`, 0–10).
    public var margin = 1

    public static let marginRange = 0...10
    /// The most characters a field keeps when it is loaded: more than any code holds (a QR code at most 4,296), so an
    /// element file from elsewhere can't make the renderer work on megabytes.
    public static let maxFieldLength = 4_296

    public init() {}

    /// Every property falls back to its default and every text is cut to `maxFieldLength`: element files and pasted
    /// elements can come from anywhere (like `AnnotationStyle.init(from:)`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BarcodeSpec()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func text(_ key: CodingKeys, _ fallback: String) -> String {
            String(value(key, fallback).prefix(Self.maxFieldLength))
        }
        symbology = value(.symbology, d.symbology)
        qrType = value(.qrType, d.qrType)
        self.text = text(.text, d.text)
        wifiSSID = text(.wifiSSID, d.wifiSSID)
        wifiPassword = text(.wifiPassword, d.wifiPassword)
        wifiEncryption = value(.wifiEncryption, d.wifiEncryption)
        vCardFirstName = text(.vCardFirstName, d.vCardFirstName)
        vCardLastName = text(.vCardLastName, d.vCardLastName)
        vCardPhone = text(.vCardPhone, d.vCardPhone)
        vCardEmail = text(.vCardEmail, d.vCardEmail)
        vCardCompany = text(.vCardCompany, d.vCardCompany)
        vCardURL = text(.vCardURL, d.vCardURL)
        epcName = text(.epcName, d.epcName)
        epcIBAN = text(.epcIBAN, d.epcIBAN)
        epcBIC = text(.epcBIC, d.epcBIC)
        epcAmount = text(.epcAmount, d.epcAmount)
        epcReference = text(.epcReference, d.epcReference)
        epcMessage = text(.epcMessage, d.epcMessage)
        emailTo = text(.emailTo, d.emailTo)
        emailSubject = text(.emailSubject, d.emailSubject)
        emailBody = text(.emailBody, d.emailBody)
        eventTitle = text(.eventTitle, d.eventTitle)
        eventLocation = text(.eventLocation, d.eventLocation)
        eventStart = text(.eventStart, d.eventStart)
        eventEnd = text(.eventEnd, d.eventEnd)
        eventDescription = text(.eventDescription, d.eventDescription)
        phoneNumber = text(.phoneNumber, d.phoneNumber)
        smsNumber = text(.smsNumber, d.smsNumber)
        smsMessage = text(.smsMessage, d.smsMessage)
        latitude = text(.latitude, d.latitude)
        longitude = text(.longitude, d.longitude)
        foreground = value(.foreground, d.foreground)
        background = value(.background, d.background)
        roundedDots = value(.roundedDots, d.roundedDots)
        margin = min(max(value(.margin, d.margin), Self.marginRange.lowerBound), Self.marginRange.upperBound)
    }
}

extension Annotation {
    /// Whether a barcode element keeps its aspect ratio when it is resized: matrix codes do (upstream
    /// `BarcodeContainer.GetScaleOptions` is `Rational` for them).
    public var barcodeKeepsAspect: Bool { kind == .barcode && barcode?.symbology.is2D == true }
}
