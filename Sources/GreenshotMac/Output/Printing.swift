// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Prints a screenshot on one page: port of upstream `Greenshot/Helpers/PrintHelper.cs` and
/// `Greenshot/Destinations/PrinterDestination.cs`. The print options (colours, footer, shrink, enlarge, rotate,
/// center) come from Settings › Printer, and are asked first when "Show print options" is on.
@MainActor
enum Printing {
    /// Set by the app delegate at launch; the editor calls `print` without settings.
    static var settings: SettingsStore?

    /// `title` and `date` fill the footer; without them an editor window's screenshot gives them.
    static func print(_ image: CGImage, scale: CGFloat, window: NSWindow?, title: String? = nil, date: Date? = nil) {
        let store = settings ?? SettingsStore()
        var title = title
        var date = date
        if title == nil, let editor = window?.windowController as? EditorWindowController {
            title = editor.editorDocument.title
            date = date ?? editor.editorDocument.captureDate
        }
        NSApp.activate()
        if store.value.printing.promptOptions {
            guard PrintOptionsDialog.run(settings: store, window: window) else { return }
        }
        let options = store.value.printing
        var footer: String?
        if options.footer {
            let context = store.patternContext(title: title, date: date ?? Date(), consumeNumber: false)
            footer = FilenamePattern.fill(options.footerPattern, context: context, filenameSafe: false)
        }

        let view = PrintPageView(image: PrintColors.apply(image, options: options), scale: scale, footer: footer, options: options)
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        // One page with the image placed by `PrintLayout`, inside the printer's printable area (like upstream).
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        if options.allowRotate {
            // Turning the page shows the right preview in the print panel; the layout rotates the image only when
            // the page chosen there still doesn't match.
            info.orientation = image.width > image.height ? .landscape : .portrait
        }
        let printable = info.imageablePageBounds
        if printable.width > 0, printable.height > 0 {
            info.leftMargin = printable.minX
            info.bottomMargin = printable.minY
            info.rightMargin = max(info.paperSize.width - printable.maxX, 0)
            info.topMargin = max(info.paperSize.height - printable.maxY, 0)
        }
        view.fit(to: info)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title ?? "Screenshot"
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}

/// The printed page: the image (and footer) placed by `PrintLayout` on the printable area of the paper.
final class PrintPageView: NSView {
    private let image: NSImage
    private let imageSize: CGSize
    private let footer: String?
    private let options: PrintSettings
    private static let footerAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black,
    ]

    init(image: CGImage, scale: CGFloat, footer: String?, options: PrintSettings) {
        imageSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        self.image = NSImage(cgImage: image, size: imageSize)
        self.footer = footer
        self.options = options
        super.init(frame: NSRect(origin: .zero, size: imageSize))
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var isFlipped: Bool { true }

    /// The page size can change in the print panel (paper, orientation), so it is read again before each layout.
    func fit(to info: NSPrintInfo) {
        let size = NSSize(width: max(info.paperSize.width - info.leftMargin - info.rightMargin, 1),
                          height: max(info.paperSize.height - info.topMargin - info.bottomMargin, 1))
        if frame.size != size { setFrameSize(size) }
    }

    private func fitToCurrentOperation() {
        if let info = NSPrintOperation.current?.printInfo { fit(to: info) }
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        fitToCurrentOperation()
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        fitToCurrentOperation()
        return bounds
    }

    var layout: PrintLayout {
        let footerSize = footer.map { ($0 as NSString).size(withAttributes: Self.footerAttributes) }
        return PrintLayout.layout(image: imageSize, page: bounds.size, footer: footerSize, options: options)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let layout = self.layout
        let rect = layout.imageRect
        if layout.rotated {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            // A quarter turn counterclockwise, like upstream's Rotate270FlipNone (the view is flipped).
            transform.rotate(byDegrees: -90)
            transform.concat()
            let turned = NSRect(x: -rect.height / 2, y: -rect.width / 2, width: rect.height, height: rect.width)
            image.draw(in: turned, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let footer, let origin = layout.footerOrigin {
            (footer as NSString).draw(at: origin, withAttributes: Self.footerAttributes)
        }
    }
}
