// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension BarcodeSpec {
    /// The text the code encodes (upstream `ZxingModel.GetPayloadString`, kept byte for byte): the plain text for every
    /// format but QR; for a QR code the text of its type, empty while the type's required field is empty.
    public var payload: String {
        guard symbology == .qrCode else { return text }
        switch qrType {
        case .text:
            return text
        case .wifi:
            guard !Self.isBlank(wifiSSID) else { return "" }
            return "WIFI:S:\(wifiSSID);T:\(wifiEncryption.payloadValue);P:\(wifiPassword);;"
        case .vCard:
            guard ![vCardFirstName, vCardLastName, vCardCompany, vCardPhone, vCardEmail].allSatisfy(Self.isBlank) else { return "" }
            let fullName = "FN:\(vCardFirstName) \(vCardLastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            return "BEGIN:VCARD\r\nVERSION:3.0\r\n" + "N:\(vCardLastName);\(vCardFirstName)\r\n" + fullName + "\r\n"
                + "ORG:\(vCardCompany)\r\n" + "TEL;TYPE=CELL:\(vCardPhone)\r\n" + "EMAIL:\(vCardEmail)\r\n"
                + "URL:\(vCardURL)\r\nEND:VCARD"
        case .epcTransfer:
            guard !(Self.isBlank(epcIBAN) && Self.isBlank(epcName)) else { return "" }
            // The European Payments Council's QR code: version 002, UTF-8, SEPA credit transfer.
            return "BCD\n002\n1\nSCT\n\(epcBIC)\n\(epcName)\n\(epcIBAN)\n\(Self.epcAmountField(epcAmount))\n\n"
                + "\(epcReference)\n\(epcMessage)\n"
        case .email:
            guard ![emailTo, emailSubject, emailBody].allSatisfy(Self.isBlank) else { return "" }
            var query: [String] = []
            if !emailSubject.isEmpty { query.append("subject=" + Self.escapedDataString(emailSubject)) }
            if !emailBody.isEmpty { query.append("body=" + Self.escapedDataString(emailBody)) }
            return "mailto:\(emailTo)" + (query.isEmpty ? "" : "?" + query.joined(separator: "&"))
        case .calendarEvent:
            guard !Self.isBlank(eventTitle) else { return "" }
            let start = eventStart.isEmpty ? "" : "DTSTART:\(eventStart)\r\n"
            let end = eventEnd.isEmpty ? "" : "DTEND:\(eventEnd)\r\n"
            return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n" + "SUMMARY:\(eventTitle)\r\n"
                + "LOCATION:\(eventLocation)\r\n" + "DESCRIPTION:\(eventDescription)\r\n" + start + end
                + "END:VEVENT\r\nEND:VCALENDAR"
        case .phone:
            return Self.isBlank(phoneNumber) ? "" : "tel:\(phoneNumber)"
        case .sms:
            return Self.isBlank(smsNumber) ? "" : "smsto:\(smsNumber):\(smsMessage)"
        case .geo:
            guard !(Self.isBlank(latitude) && Self.isBlank(longitude)) else { return "" }
            return "geo:\(latitude),\(longitude)"
        }
    }

    /// What to fill in while there is nothing to encode (upstream `ZxingEditorWindow.GetRequiredInputHint`).
    public var requiredInputHint: String {
        guard symbology == .qrCode else { return "Please enter a value to generate the barcode." }
        switch qrType {
        case .text: return "Please enter text or a URL."
        case .wifi: return "Please enter network name (SSID)."
        case .vCard: return "Please enter contact name or details."
        case .epcTransfer: return "Please enter recipient name and IBAN."
        case .email: return "Please enter recipient email address."
        case .calendarEvent: return "Please enter event title."
        case .phone: return "Please enter a phone number."
        case .sms: return "Please enter recipient number."
        case .geo: return "Please enter latitude and longitude coordinates."
        }
    }

    /// .NET `string.IsNullOrWhiteSpace`.
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The amount line of an EPC code: a number (in the user's or the POSIX format) as `EUR` with two decimals, other
    /// text as typed with `EUR` in front unless it starts with it (upstream: `double.TryParse` in the current culture,
    /// formatted `EUR{0:F2}` invariant).
    static func epcAmountField(_ typed: String, locale: Locale = .current) -> String {
        if let amount = number(typed, locale: locale) {
            return String(format: "EUR%.2f", amount)
        }
        guard !typed.isEmpty else { return "" }
        return typed.uppercased().hasPrefix("EUR") ? typed : "EUR" + typed
    }

    private static func number(_ typed: String, locale: Locale) -> Double? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let value = formatter.number(from: trimmed)?.doubleValue ?? Double(trimmed)
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// .NET `Uri.EscapeDataString`: everything but the RFC 3986 unreserved ASCII characters is percent-encoded as UTF-8
    /// (`CharacterSet.alphanumerics` would let other alphabets through).
    static func escapedDataString(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

extension BarcodeSymbology {
    /// The name in upstream's format list.
    public var title: String {
        switch self {
        case .qrCode: return "QR Code"
        case .aztec: return "Aztec (2D)"
        case .dataMatrix: return "Data Matrix (2D)"
        case .pdf417: return "PDF-417 (2D)"
        case .code128: return "Code 128 (1D)"
        case .code39: return "Code 39 (1D)"
        case .code93: return "Code 93 (1D)"
        case .ean13: return "EAN-13 (1D)"
        case .ean8: return "EAN-8 (1D)"
        case .upcA: return "UPC-A (1D)"
        case .upcE: return "UPC-E (1D)"
        case .codabar: return "Codabar (1D)"
        case .itf: return "ITF (1D)"
        case .msi: return "MSI (1D)"
        case .plessey: return "Plessey (1D)"
        }
    }
}

extension QRPayloadType {
    /// The name in upstream's QR Type list.
    public var title: String {
        switch self {
        case .text: return "Text / URL"
        case .wifi: return "WiFi Network"
        case .vCard: return "vCard Contact"
        case .epcTransfer: return "EPC SEPA Transfer"
        case .email: return "Email"
        case .calendarEvent: return "Calendar Event"
        case .phone: return "Phone Call"
        case .sms: return "SMS"
        case .geo: return "Geo Location"
        }
    }

    /// The title of the box with the type's fields (upstream `GrpInputs.Header`).
    public var fieldsTitle: String {
        switch self {
        case .text: return "Raw Text or URL Details"
        case .wifi: return "WiFi Network Connection Details"
        case .vCard: return "vCard Contact Card Details"
        case .epcTransfer: return "EPC SEPA Credit Transfer Details"
        case .email: return "Email Message Details"
        case .calendarEvent: return "Calendar Event (iCal) Details"
        case .phone: return "Phone Call Details"
        case .sms: return "SMS Text Message Details"
        case .geo: return "Geo Location Details"
        }
    }
}

extension WiFiEncryption {
    /// The name in upstream's Encryption Type list.
    public var title: String {
        switch self {
        case .wpa: return "WPA/WPA2"
        case .wep: return "WEP"
        case .unencrypted: return "Unencrypted (None)"
        }
    }

    /// The `T:` value of a WiFi code.
    public var payloadValue: String {
        switch self {
        case .wpa: return "WPA"
        case .wep: return "WEP"
        case .unencrypted: return "nopass"
        }
    }
}
