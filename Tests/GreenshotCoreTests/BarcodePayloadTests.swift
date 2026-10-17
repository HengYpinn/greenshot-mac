// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

/// The QR code contents of upstream `ZxingModel.GetPayloadString` and the element model's loading.
struct BarcodePayloadTests {
    func qr(_ type: QRPayloadType, _ change: (inout BarcodeSpec) -> Void) -> BarcodeSpec {
        var spec = BarcodeSpec()
        spec.qrType = type
        change(&spec)
        return spec
    }

    @Test func theDialogStartsLikeUpstream() {
        let spec = BarcodeSpec()
        #expect(spec.symbology == .qrCode)
        #expect(spec.qrType == .text)
        #expect(spec.payload == "https://getgreenshot.org")
        #expect(spec.margin == 1)
        #expect(spec.foreground == .black)
        #expect(spec.background == .white)
        #expect(!spec.roundedDots)
        #expect(spec.epcAmount == "10.00")
    }

    @Test func otherFormatsEncodeTheTextAsTyped() {
        var spec = qr(.wifi) { $0.text = " 4006381333931 " }
        spec.symbology = .ean13
        #expect(spec.payload == " 4006381333931 ")
        #expect(spec.requiredInputHint == "Please enter a value to generate the barcode.")
    }

    @Test func wifi() {
        let wpa = qr(.wifi) { $0.wifiSSID = "Home"; $0.wifiPassword = "secret" }
        #expect(wpa.payload == "WIFI:S:Home;T:WPA;P:secret;;")
        let wep = qr(.wifi) { $0.wifiSSID = "Old"; $0.wifiPassword = "abc"; $0.wifiEncryption = .wep }
        #expect(wep.payload == "WIFI:S:Old;T:WEP;P:abc;;")
        let open = qr(.wifi) { $0.wifiSSID = "Cafe"; $0.wifiEncryption = .unencrypted }
        #expect(open.payload == "WIFI:S:Cafe;T:nopass;P:;;")
        #expect(qr(.wifi) { $0.wifiSSID = "  "; $0.wifiPassword = "x" }.payload.isEmpty)
    }

    @Test func vCard() {
        let card = qr(.vCard) {
            $0.vCardFirstName = "Ada"; $0.vCardLastName = "Lovelace"; $0.vCardPhone = "+44 20"
            $0.vCardEmail = "ada@example.com"; $0.vCardCompany = "Engines"; $0.vCardURL = "https://example.com"
        }
        let expected = "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Lovelace;Ada\r\nFN:Ada Lovelace\r\nORG:Engines\r\n"
            + "TEL;TYPE=CELL:+44 20\r\nEMAIL:ada@example.com\r\nURL:https://example.com\r\nEND:VCARD"
        #expect(card.payload == expected)
        // Upstream trims "FN:Ada " (no last name) to "FN:Ada".
        let first = qr(.vCard) { $0.vCardFirstName = "Ada" }
        #expect(first.payload.contains("\r\nFN:Ada\r\n"))
        // The URL alone is not enough.
        #expect(qr(.vCard) { $0.vCardURL = "https://example.com" }.payload.isEmpty)
    }

    @Test func epcTransfer() {
        let transfer = qr(.epcTransfer) {
            $0.epcName = "Red Cross"; $0.epcIBAN = "BE72000000001616"; $0.epcBIC = "BPOTBEB1"
            $0.epcAmount = "10"; $0.epcReference = "REF1"; $0.epcMessage = "Thanks"
        }
        #expect(transfer.payload == "BCD\n002\n1\nSCT\nBPOTBEB1\nRed Cross\nBE72000000001616\nEUR10.00\n\nREF1\nThanks\n")
        #expect(qr(.epcTransfer) { $0.epcName = " " }.payload.isEmpty)
        let ibanOnly = qr(.epcTransfer) { $0.epcIBAN = "DE02"; $0.epcAmount = "" }
        #expect(ibanOnly.payload == "BCD\n002\n1\nSCT\n\n\nDE02\n\n\n\n\n")
    }

    @Test func epcAmountsLikeDoubleTryParse() {
        let german = Locale(identifier: "de_DE")
        let posix = Locale(identifier: "en_US_POSIX")
        #expect(BarcodeSpec.epcAmountField("12,5", locale: german) == "EUR12.50")
        #expect(BarcodeSpec.epcAmountField("12.5", locale: posix) == "EUR12.50")
        #expect(BarcodeSpec.epcAmountField(" 3 ", locale: posix) == "EUR3.00")
        #expect(BarcodeSpec.epcAmountField("EUR7", locale: posix) == "EUR7")
        #expect(BarcodeSpec.epcAmountField("eur7", locale: posix) == "eur7")
        #expect(BarcodeSpec.epcAmountField("seven", locale: posix) == "EURseven")
        #expect(BarcodeSpec.epcAmountField("", locale: posix) == "")
        #expect(BarcodeSpec.epcAmountField("inf", locale: posix) == "EURinf")
    }

    @Test func email() {
        let mail = qr(.email) { $0.emailTo = "a@b.c"; $0.emailSubject = "Hi there"; $0.emailBody = "a b&c/ü~" }
        #expect(mail.payload == "mailto:a@b.c?subject=Hi%20there&body=a%20b%26c%2F%C3%BC~")
        #expect(qr(.email) { $0.emailTo = "a@b.c" }.payload == "mailto:a@b.c")
        #expect(qr(.email) { $0.emailSubject = "Only" }.payload == "mailto:?subject=Only")
        #expect(qr(.email) { $0.emailBody = " " }.payload.isEmpty)
    }

    @Test func calendarEvent() {
        let event = qr(.calendarEvent) {
            $0.eventTitle = "Launch"; $0.eventLocation = "Here"; $0.eventDescription = "Party"
            $0.eventStart = "20261017T090000Z"; $0.eventEnd = "20261017T100000Z"
        }
        let expected = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nSUMMARY:Launch\r\nLOCATION:Here\r\n"
            + "DESCRIPTION:Party\r\nDTSTART:20261017T090000Z\r\nDTEND:20261017T100000Z\r\nEND:VEVENT\r\nEND:VCALENDAR"
        #expect(event.payload == expected)
        let bare = qr(.calendarEvent) { $0.eventTitle = "T" }
        #expect(bare.payload == "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nSUMMARY:T\r\nLOCATION:\r\nDESCRIPTION:\r\nEND:VEVENT\r\nEND:VCALENDAR")
        #expect(qr(.calendarEvent) { $0.eventLocation = "Here" }.payload.isEmpty)
    }

    @Test func phoneSmsAndGeo() {
        #expect(qr(.phone) { $0.phoneNumber = "+1 555" }.payload == "tel:+1 555")
        #expect(qr(.phone) { _ in }.payload.isEmpty)
        #expect(qr(.sms) { $0.smsNumber = "123"; $0.smsMessage = "Hello" }.payload == "smsto:123:Hello")
        #expect(qr(.sms) { $0.smsMessage = "Hello" }.payload.isEmpty)
        #expect(qr(.geo) { $0.latitude = "52.5"; $0.longitude = "13.4" }.payload == "geo:52.5,13.4")
        #expect(qr(.geo) { $0.latitude = "52.5" }.payload == "geo:52.5,")
        #expect(qr(.geo) { _ in }.payload.isEmpty)
    }

    @Test func hintsAreUpstreams() {
        #expect(qr(.text) { _ in }.requiredInputHint == "Please enter text or a URL.")
        #expect(qr(.wifi) { _ in }.requiredInputHint == "Please enter network name (SSID).")
        #expect(qr(.epcTransfer) { _ in }.requiredInputHint == "Please enter recipient name and IBAN.")
        #expect(qr(.geo) { _ in }.requiredInputHint == "Please enter latitude and longitude coordinates.")
    }

    @Test func upstreamIndexes() {
        #expect(BarcodeSymbology.allCases.count == 15)
        #expect(BarcodeSymbology(upstreamIndex: 0) == .qrCode)
        #expect(BarcodeSymbology(upstreamIndex: 4) == .code128)
        #expect(BarcodeSymbology(upstreamIndex: 14) == .plessey)
        #expect(BarcodeSymbology(upstreamIndex: 15) == nil)
        #expect(BarcodeSymbology.dataMatrix.upstreamIndex == 2)
        #expect(QRPayloadType(upstreamIndex: 8) == .geo)
        #expect(QRPayloadType.epcTransfer.upstreamIndex == 3)
        #expect(BarcodeSymbology.allCases.filter(\.is2D) == [.qrCode, .aztec, .dataMatrix, .pdf417])
    }

    @Test func specsRoundTrip() throws {
        var spec = qr(.wifi) { $0.wifiSSID = "Home"; $0.margin = 4; $0.roundedDots = true }
        spec.foreground = RGBAColor(red: 0, green: 0, blue: 0.5)
        let data = try JSONEncoder().encode(spec)
        let back = try JSONDecoder().decode(BarcodeSpec.self, from: data)
        #expect(back == spec)
    }

    @Test func loadingIsTolerantAndLimited() throws {
        let junk = #"{"symbology":"nope","qrType":7,"margin":99,"text":"x","roundedDots":"yes"}"#
        let spec = try JSONDecoder().decode(BarcodeSpec.self, from: Data(junk.utf8))
        #expect(spec.symbology == .qrCode)
        #expect(spec.qrType == .text)
        #expect(spec.margin == 10)
        #expect(spec.text == "x")
        #expect(!spec.roundedDots)
        let negative = try JSONDecoder().decode(BarcodeSpec.self, from: Data(#"{"margin":-3}"#.utf8))
        #expect(negative.margin == 0)
        #expect(negative.text == "https://getgreenshot.org")
        let huge = try JSONEncoder().encode(["smsMessage": String(repeating: "a", count: 1_000_000)])
        let cut = try JSONDecoder().decode(BarcodeSpec.self, from: huge)
        #expect(cut.smsMessage.count == BarcodeSpec.maxFieldLength)
    }

    @Test func elementsKeepTheirSpecAndOldOnesStillLoad() throws {
        var element = Annotation(kind: .barcode, start: .zero, end: CGPoint(x: 10, y: 10))
        element.barcode = qr(.phone) { $0.phoneNumber = "1" }
        let back = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(element))
        #expect(back == element)
        let picture = Annotation(kind: .image, start: .zero, end: CGPoint(x: 10, y: 10))
        let old = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(picture))
        #expect(old.barcode == nil)
    }
}
