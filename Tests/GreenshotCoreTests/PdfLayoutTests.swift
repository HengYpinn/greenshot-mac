// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct PdfLayoutTests {
    @Test func imageSizePageAddsTheMargins() {
        var s = PDFSettings()
        s.unit = .inch
        s.marginLeft = 1
        s.marginTop = 0.5
        let layout = PdfLayout.layout(image: CGSize(width: 200, height: 100), settings: s)
        #expect(layout.pageSize == CGSize(width: 272, height: 136))
        #expect(layout.imageRect == CGRect(x: 72, y: 0, width: 200, height: 100))
    }

    @Test func presetSizes() {
        let a4 = PdfLayout.layout(image: CGSize(width: 10, height: 10), settings: { var s = PDFSettings(); s.pageSize = .a4; return s }())
        #expect(abs(a4.pageSize.width - 595.28) < 0.01 && abs(a4.pageSize.height - 841.89) < 0.01)
        let letter = PdfLayout.layout(image: CGSize(width: 10, height: 10), settings: { var s = PDFSettings(); s.pageSize = .letter; return s }())
        #expect(abs(letter.pageSize.width - 612) < 0.01 && abs(letter.pageSize.height - 792) < 0.01)
        #expect(PdfLayout.presetMillimetres(.a3) == CGSize(width: 297, height: 420))
        #expect(PdfLayout.presetMillimetres(.a6) == CGSize(width: 105, height: 148))
    }

    @Test func shrinkOnlyKeepsSmallImagesAndCentresThem() {
        var s = PDFSettings()
        s.pageSize = .custom
        s.unit = .inch
        s.customWidth = 4
        s.customHeight = 2
        let small = PdfLayout.layout(image: CGSize(width: 100, height: 50), settings: s)
        #expect(small.imageRect == CGRect(x: 94, y: 47, width: 100, height: 50))
        let big = PdfLayout.layout(image: CGSize(width: 576, height: 144), settings: s)
        #expect(big.imageRect == CGRect(x: 0, y: 36, width: 288, height: 72))
    }

    @Test func fitToPageEnlargesWithinTheMargins() {
        var s = PDFSettings()
        s.pageSize = .custom
        s.unit = .inch
        s.customWidth = 4
        s.customHeight = 2
        s.marginTop = 0.5
        s.marginBottom = 0.5
        s.scaling = .fitToPage
        let layout = PdfLayout.layout(image: CGSize(width: 100, height: 50), settings: s)
        // 288 × 72 points are free: the height limits, 144 × 72, centred.
        #expect(layout.imageRect == CGRect(x: 72, y: 36, width: 144, height: 72))
    }

    @Test func writesAOnePagePDF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("greenshot-test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try PdfLayout.write(TestImage.solid(width: 20, height: 10, .red), scale: 2, settings: PDFSettings(), title: "Test", to: url)
        let document = try #require(CGPDFDocument(url as CFURL))
        #expect(document.numberOfPages == 1)
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == CGSize(width: 10, height: 5))
    }
}
