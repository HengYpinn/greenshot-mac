// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Prints a screenshot on one page: port of upstream `Greenshot/Helpers/PrintHelper.cs` and
/// `Greenshot/Destinations/PrinterDestination.cs`. The print options (colours, footer, shrink, enlarge, rotate,
/// center) come from Settings › Printer, or a recipe's for its print, and are asked first when "Show print options" is
/// on.
@MainActor
enum Printing {
    /// Set by the app delegate at launch; the editor calls `print` without settings.
    static var settings: SettingsStore?

    /// The installed printers, the default one first (upstream `PrinterDestination.GetDynamicDestinationsAsync`).
    static func printerNames() -> [String] {
        DestinationSupport.sortedPrinters(NSPrinter.printerNames, defaultPrinter: NSPrintInfo.defaultPrinter?.name)
    }

    /// `title` and `date` fill the footer; without them an editor window's screenshot gives them. With `printer` it
    /// prints there without the print panel (upstream `PrintHelper.PrintTo`). `options` are the print options of this
    /// print only (a recipe's, upstream `PrintHelper`'s `PrintOptions`); without them Settings › Printer's.
    /// `completion` says whether it was printed.
    static func print(_ image: CGImage, scale: CGFloat, window: NSWindow?, title: String? = nil, date: Date? = nil,
                      printer: String? = nil, options given: PrintSettings? = nil, completion: ((ExportResult) -> Void)? = nil) {
        let store = settings ?? SettingsStore()
        var title = title
        var date = date
        if title == nil, let editor = window?.windowController as? EditorWindowController {
            title = editor.editorDocument.title
            date = date ?? editor.editorDocument.captureDate
        }
        NSApp.activate()
        // What an administrator locked wins over a recipe's options and the dialog's, like in Settings › Printer.
        func locked(_ options: PrintSettings) -> PrintSettings {
            RecipePrintOptions.enforcingLocks(options, policy: store.policy, settings: store.value)
        }
        var options = locked(given ?? store.value.printing)
        if options.promptOptions {
            if given != nil {
                // This print's options: asked, not saved.
                guard let asked = PrintOptionsDialog.ask(options, policy: store.policy, window: window) else {
                    completion?(.declined)
                    return
                }
                options = locked(asked)
            } else {
                guard PrintOptionsDialog.run(settings: store, window: window) else {
                    completion?(.declined)
                    return
                }
                options = locked(store.value.printing)
            }
        }
        var footer: String?
        if options.footer {
            let context = store.patternContext(title: title, date: date ?? Date(), consumeNumber: false)
            let text = FilenamePattern.fill(options.footerPattern, context: context, filenameSafe: false)
            // An empty footer takes no room, like upstream's `MeasureString("")` (an empty NSString still measures a line).
            footer = text.isEmpty ? nil : text
        }

        let view = PrintPageView(image: PrintColors.apply(image, options: options), scale: scale, footer: footer, options: options)
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        if let printer {
            guard let chosen = NSPrinter(name: printer) else {
                ErrorPresenter.show(message: String(localized: "The printer “\(printer)” is not there any more"),
                                    detail: String(localized: "Choose another one.", comment: "Choose another printer"))
                completion?(.failed(String(localized: "The printer “\(printer)” is not there any more."), target: printer))
                return
            }
            info.printer = chosen
        }
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
        operation.showsPrintPanel = printer == nil
        operation.showsProgressPanel = true
        let finish: (Bool) -> Void = { printed in
            guard printed else {
                completion?(.declined)
                return
            }
            // Upstream `senttoprinter`.
            let name = operation.printInfo.printer.name
            ImageSaver(settings: store).notify(String(localized: "Sent to the printer “\(name)”"))
            completion?(.succeeded(target: name))
        }
        if let window {
            PrintRun.start(operation, for: window, finish: finish)
        } else {
            finish(operation.run())
        }
    }
}

/// Waits for a print operation run as a sheet.
@MainActor
private final class PrintRun: NSObject {
    private static var running: Set<PrintRun> = []
    private let finish: (Bool) -> Void

    private init(finish: @escaping (Bool) -> Void) {
        self.finish = finish
    }

    static func start(_ operation: NSPrintOperation, for window: NSWindow, finish: @escaping (Bool) -> Void) {
        let run = PrintRun(finish: finish)
        running.insert(run)
        operation.runModal(for: window, delegate: run, didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                           contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Self.running.remove(self)
        finish(success)
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
