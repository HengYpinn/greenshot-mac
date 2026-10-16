// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import CoreImage
import Foundation
import Testing
@testable import GreenshotCore

struct RecognitionTests {
    /// A white image with black text drawn on it.
    private func textImage(_ text: String, width: Int = 600, height: Int = 120) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 20, y: 35))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    @Test func recognizesALineAndItsWords() throws {
        let lines = try TextRecognizer.recognizeLines(in: textImage("Hello Greenshot 2026"))
        let line = try #require(lines.first)
        #expect(line.text.contains("Hello"))
        #expect(line.text.contains("2026"))
        #expect(line.words.count == 3)
        #expect(line.bounds.minX >= 0 && line.bounds.maxX <= 600 && line.bounds.height < 120)
        // Words follow each other left to right inside the line.
        let xs = line.words.map(\.bounds.minX)
        #expect(xs == xs.sorted())
        #expect(line.words.allSatisfy { line.bounds.insetBy(dx: -4, dy: -4).contains($0.bounds) })
    }

    @Test func recognizeTextJoinsLines() throws {
        let text = try TextRecognizer.recognizeText(in: textImage("Line one"))
        #expect(text.lowercased().contains("line one"))
    }

    @Test func visionBoxesAreFlippedToTopLeftOrigin() {
        // A box in the top quarter of a normalised image is near y = 0 in pixels.
        let r = TextRecognizer.pixelRect(CGRect(x: 0.1, y: 0.75, width: 0.5, height: 0.25), width: 200, height: 100)
        #expect(r == CGRect(x: 20, y: 0, width: 100, height: 25))
    }

    @Test func wordRangesSplitOnWhitespace() {
        let text = "a  bc\td"
        #expect(TextRecognizer.wordRanges(in: text).map { String(text[$0]) } == ["a", "bc", "d"])
    }

    @Test func detectsAQRCodeAndItsURL() throws {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("https://getgreenshot.org/".utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let output = try #require(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        // Put it on a bigger white canvas, off centre, so the bounds mean something.
        let canvas = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let composed = output.transformed(by: CGAffineTransform(translationX: 300, y: 50)).composited(over: canvas)
        let image = try #require(CIContext().createCGImage(composed, from: canvas.extent))
        let codes = try BarcodeDetector.detect(in: image)
        let code = try #require(codes.first)
        #expect(code.payload == "https://getgreenshot.org/")
        #expect(code.url?.host == "getgreenshot.org")
        #expect(code.symbology == "QR")
        // Vision's origin is bottom left; ours top left: the code sits at x ≥ 300 and in the lower part (y > 100).
        #expect(code.bounds.minX >= 290 && code.bounds.minY > 100)
    }

    @Test func plainTextPayloadHasNoURL() {
        #expect(DetectedBarcode(payload: "hello world", bounds: .zero, symbology: "QR").url == nil)
        #expect(DetectedBarcode(payload: "mailto:a@b.c", bounds: .zero, symbology: "QR").url != nil)
    }
}

struct NewSettingsTests {
    @Test func newFieldsHaveUpstreamDefaults() {
        let s = AppSettings()
        #expect(s.fixedCaptureSizes == CaptureSize.defaults)
        #expect(s.fixedCaptureAnchor == .topLeft && s.screenCaptureMode == .fullScreen && s.screenToCapture == 1)
        #expect(s.captureHelpVisible && s.captureInfoVisible && s.captureSelectionPreviewVisible)
        #expect(s.ocrLanguage.isEmpty && s.scanQRCodesOnCapture && s.autoCropDifference == 10)
        #expect(s.notificationLevel == .all)
        #expect(!s.reuseEditor && !s.suppressSaveDialogAtClose && s.matchSizeToCapture)
        #expect(s.dropShadowSettings == DropShadowSettings(darkness: 0.6, size: 7, offsetX: -1, offsetY: -1))
        #expect(s.tornEdgeSettings.toothHeight == 12 && s.tornEdgeSettings.horizontalToothRange == 20 && s.tornEdgeSettings.shadow)
        #expect(s.allowOverwrite && !s.promptJpegQuality && !s.reduceColors && s.reduceColorsTo == 256)
        #expect(s.clipboardFormats == [.png, .tiff])
        #expect(s.printing.promptOptions && s.printing.footer && s.printing.allowShrink && !s.printing.allowEnlarge && s.printing.center)
        #expect(s.printing.footerPattern == "${capturetime:d\"D\"} ${capturetime:d\"T\"} - ${title}")
        #expect(s.email.subjectPattern == "${title}")
        #expect(s.externalCommands.first?.name == "Preview")
        #expect(s.pdf.pageSize == .image && s.pdf.unit == .mm && s.pdf.customWidth == 210 && s.pdf.scaling == .shrinkToFit)
        #expect(s.updateCheckIntervalDays == 14 && s.lastUpdateCheck == nil)
    }

    @Test func newFieldsRoundTrip() throws {
        var s = AppSettings()
        s.fixedCaptureSizes = [CaptureSize(width: 300, height: 200)]
        s.recentCaptureSizes = [CaptureSize(width: 10, height: 20)]
        s.fixedCaptureSize = CaptureSize(width: 10, height: 20)
        s.fixedCaptureAnchor = .center
        s.screenCaptureMode = .fixed
        s.notificationLevel = .errors
        s.tornEdgeSettings.left = false
        s.textObfuscation.searchPattern = "secret"
        s.printing.monochrome = true
        s.email.to = "a@b.c"
        s.externalCommands.append(ExternalCommand(name: "Echo", command: "/bin/echo"))
        s.pdf.pageSize = .a4
        s.lastUpdateCheck = Date(timeIntervalSince1970: 1_000_000)
        s.lastSavedFile = "/tmp/x.png"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }

    @Test func settingsFromAnOlderVersionStillLoad() throws {
        let json = #"{"outputFolder": "~/Pictures", "fixedCaptureAnchor": "nowhere", "pdf": {"pageSize": "a4"}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.outputFolder == "~/Pictures")
        #expect(decoded.fixedCaptureAnchor == .topLeft)
        #expect(decoded.fixedCaptureSizes == CaptureSize.defaults)
        // A partial nested struct falls back as a whole (every field of it has a default anyway).
        #expect(decoded.pdf.pageSize == .image || decoded.pdf.pageSize == .a4)
    }

    @Test func captureSizeParsing() {
        #expect(CaptureSize("640x480") == CaptureSize(width: 640, height: 480))
        #expect(CaptureSize(" 1920 X 1080 ") == CaptureSize(width: 1920, height: 1080))
        #expect(CaptureSize("0x10") == nil && CaptureSize("abc") == nil)
        #expect(CaptureSize(width: 640, height: 480).displayString == "640×480")
        #expect(FixedCaptureAnchor.center.next == .topLeft && FixedCaptureAnchor.topLeft.next == .topRight)
    }
}
