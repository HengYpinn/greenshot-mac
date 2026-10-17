// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// `GreenshotMac --snapshot <folder>` renders the editor, the capture screen and the settings offscreen to PNG
/// files and quits. It needs no screen recording permission, so contributors and CI can look at UI changes.
@MainActor
enum Snapshots {
    static var requestedFolder: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func render(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "greenshot-mac-snapshots")!
        defaults.removePersistentDomain(forName: "greenshot-mac-snapshots")
        let settings = SettingsStore(defaults: defaults)
        let sample = sampleImage(width: 1280, height: 800)

        try write(editor(sample: sample, settings: settings), to: folder.appendingPathComponent("editor.png"))
        try write(effectsEditor(sample: sample, settings: settings), to: folder.appendingPathComponent("editor-effects.png"))
        try write(overlay(sample: sample, mode: .region), to: folder.appendingPathComponent("capture-region.png"))
        try write(overlay(sample: sample, mode: .window), to: folder.appendingPathComponent("capture-window.png"))
        try write(overlay(sample: sample, mode: .fixedSize), to: folder.appendingPathComponent("capture-fixed-size.png"))
        try write(overlay(sample: sample, mode: .text), to: folder.appendingPathComponent("capture-text.png"))
        try write(overlay(sample: sample, mode: .region, qrCode: true), to: folder.appendingPathComponent("capture-qr.png"))
        for (index, name) in ["general", "capture", "output", "destinations", "editor", "printer", "expert"].enumerated() {
            try write(settingsTab(index, settings: settings), to: folder.appendingPathComponent("settings-\(name).png"))
        }
        for (name, view) in dialogs(sample: sample) {
            try write(form(view), to: folder.appendingPathComponent("dialog-\(name).png"))
        }
        // Each area adds its own renders in its Snapshots+<Area>.swift file.
        try renderCaptureExtras(to: folder, sample: sample, settings: settings)
        try renderCanvasExtras(to: folder, sample: sample, settings: settings)
        try renderEditorWindowExtras(to: folder, sample: sample, settings: settings)
        try renderImageExtras(to: folder, sample: sample, settings: settings)
        try renderOutputExtras(to: folder, sample: sample, settings: settings)
        try renderAppExtras(to: folder, sample: sample, settings: settings)
        try renderNotificationExtras(to: folder, sample: sample, settings: settings)
        try renderBarcodeExtras(to: folder, sample: sample, settings: settings)
        if let editorDocument {
            try ImageExporter.write(editorDocument.flattened(), to: folder.appendingPathComponent("editor-export.png"), format: .png,
                                    scale: editorDocument.scale)
        }
    }

    private static var editorDocument: EditorDocument?

    private static func editor(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        editorDocument = doc
        func style(_ kind: AnnotationKind, _ change: (inout AnnotationStyle) -> Void = { _ in }) -> AnnotationStyle {
            var s = AnnotationStyle.defaults(for: kind)
            change(&s)
            return s
        }
        let arrow = Annotation(kind: .arrow, start: CGPoint(x: 1500, y: 1250), end: CGPoint(x: 1120, y: 980))
        doc.add(Annotation(kind: .rectangle, start: CGPoint(x: 160, y: 300), end: CGPoint(x: 1100, y: 700)))
        doc.add(Annotation(kind: .highlight, start: CGPoint(x: 180, y: 815), end: CGPoint(x: 1060, y: 868)))
        doc.add(Annotation(kind: .obfuscate, start: CGPoint(x: 180, y: 872), end: CGPoint(x: 1120, y: 925),
                           style: style(.obfuscate) { $0.pixelSize = 8 }))
        doc.add(arrow)
        doc.add(Annotation(kind: .text, start: CGPoint(x: 1380, y: 1260), end: CGPoint(x: 2100, y: 1360),
                           text: "Personal data hidden", style: style(.text) { $0.fontSize = 22; $0.bold = true }))
        doc.add(Annotation(kind: .counter, start: CGPoint(x: 100, y: 240), end: CGPoint(x: 160, y: 300)))
        doc.add(Annotation(kind: .counter, start: CGPoint(x: 1110, y: 800), end: CGPoint(x: 1170, y: 860)))
        doc.add(Annotation(kind: .ellipse, start: CGPoint(x: 1700, y: 280), end: CGPoint(x: 2400, y: 620),
                           style: style(.ellipse) { $0.lineColor = .blue; $0.lineWidth = 3 }))
        doc.add(Annotation(kind: .freehand, start: .zero, end: .zero,
                           points: stride(from: 0, through: 60, by: 1).map { i in
                               CGPoint(x: 1750 + CGFloat(i) * 10, y: 1500 + sin(CGFloat(i) / 4) * 40)
                           }))
        let bubble = Annotation(kind: .speechBubble, start: CGPoint(x: 1560, y: 760), end: CGPoint(x: 2340, y: 960),
                                text: "Best quarter yet!", tail: CGPoint(x: 1900, y: 640))
        doc.add(bubble)
        doc.add(Annotation(kind: .emoji, start: CGPoint(x: 2140, y: 1246), end: CGPoint(x: 2268, y: 1374), text: "🙈"))

        return editorWindow(doc, settings: settings) { controller in
            controller.canvas.tool = .speechBubble
            controller.canvas.select(bubble.id)
        }
    }

    /// The editor after the torn edge effect drawn into the pixels (Effects › Torn Edges now adds an element instead),
    /// with the elements moved along.
    private static func effectsEditor(sample: CGImage, settings: SettingsStore) -> NSBitmapImageRep? {
        let doc = EditorDocument(image: sample, scale: 2, title: "Snapshot")
        doc.add(Annotation(kind: .speechBubble, start: CGPoint(x: 1500, y: 1180), end: CGPoint(x: 2300, y: 1400),
                           text: "Torn edges, drop shadow", tail: CGPoint(x: 1200, y: 1500)))
        doc.add(Annotation(kind: .emoji, start: CGPoint(x: 2340, y: 1220), end: CGPoint(x: 2480, y: 1360), text: "✂️"))
        doc.apply(.tornEdge, seed: 2026)
        return editorWindow(doc, settings: settings) { $0.canvas.tool = .select }
    }

    static func editorWindow(_ doc: EditorDocument, settings: SettingsStore,
                                     configure: (EditorWindowController) -> Void) -> NSBitmapImageRep? {
        let saver = ImageSaver(settings: settings)
        let controller = EditorWindowController(document: doc, settings: settings, saver: saver) { _ in }
        guard let window = controller.window, let content = window.contentView else { return nil }
        window.setContentSize(NSSize(width: 1180, height: 760))
        configure(controller)
        content.layoutSubtreeIfNeeded()
        controller.zoomToFit(nil)
        content.layoutSubtreeIfNeeded()
        return capture(content)
    }

    /// The dialogs (their forms, without the alert around them): print options, the effect settings, resize, adjust
    /// and text obfuscation.
    static func dialogs(sample: CGImage) -> [(String, NSView)] {
        let printOptions = PrintOptionsForm(options: PrintSettings())
        let dropShadow = DropShadowSettingsForm(DropShadowSettings())
        let tornEdge = TornEdgeSettingsForm(TornEdgeSettings())
        let resize = ResizeForm(size: CGSize(width: 2560, height: 1600))
        let adjust = AdjustSettingsForm()
        let obfuscate = TextObfuscationSheet(image: sample, settings: TextObfuscationSettings(), language: "")
        obfuscate.showAdvanced()
        // The forms own their controls; keep them alive until the renders are written.
        keepAlive += [printOptions, dropShadow, tornEdge, resize, adjust, obfuscate]
        return [("print-options", printOptions.view), ("drop-shadow", dropShadow.view), ("torn-edges", tornEdge.view),
                ("resize", resize.view), ("adjust", adjust.view), ("obfuscate-text", obfuscate.contentView ?? NSView())]
    }

    static var keepAlive: [AnyObject] = []

    static func form(_ view: NSView) -> NSBitmapImageRep? {
        view.appearance = NSAppearance(named: .aqua)
        view.layoutSubtreeIfNeeded()
        if view.frame.isEmpty { view.frame.size = view.fittingSize }
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        return capture(view)
    }

    static func overlay(sample: CGImage, mode: CaptureOverlayController.Mode, qrCode: Bool = false) -> NSBitmapImageRep? {
        let screen = FrozenScreen(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1280, height: 800), scale: 2, image: sample)
        let windows = [WindowInfo(id: 1, frame: CGRect(x: 50, y: 50, width: 1140, height: 690), title: "Quarterly report",
                                  appName: "Preview", pid: 1)]
        let controller = CaptureOverlayController(screens: [screen], windows: windows, mode: .region, zoomer: true) { _ in }
        let view = OverlayMarksView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), frozen: screen, controller: controller)
        switch mode {
        case .region where qrCode:
            // A made-up QR code frame over the orange shape, with its menu open.
            let code = DetectedBarcode(payload: "https://getgreenshot.org/", bounds: CGRect(x: 880, y: 160, width: 220, height: 160), symbology: "QR")
            controller.useBarcodes([code])
            controller.mouseMoved(to: CGPoint(x: 990, y: 240))
            controller.openBarcodeMenu(for: code, at: CGPoint(x: 990, y: 240))
        case .region:
            controller.mouseDown(at: CGPoint(x: 90, y: 160))
            controller.mouseDragged(to: CGPoint(x: 560, y: 470), shift: false)
        case .window:
            controller.switchMode(to: .window)
            controller.mouseMoved(to: CGPoint(x: 700, y: 400))
        case .fixedSize:
            controller.switchMode(to: .fixedSize)
            controller.mouseMoved(to: CGPoint(x: 300, y: 220))
        case .text:
            // The sample's text lines, as text recognition would report them (global points).
            let texts = ["Revenue grew in every region this quarter.", "Contact: support@example.com  Order 4711-0815",
                         "Next review: Thursday at 10:00"]
            let lines = texts.enumerated().map { index, text -> RecognizedLine in
                let bounds = CGRect(x: 100, y: 410 + CGFloat(index) * 30, width: CGFloat(text.count) * 10, height: 24)
                var x = bounds.minX
                let words = text.split(separator: " ").map { word -> RecognizedWord in
                    let w = RecognizedWord(text: String(word), bounds: CGRect(x: x, y: bounds.minY, width: CGFloat(word.count) * 10, height: 24))
                    x += CGFloat(word.count + 1) * 10
                    return w
                }
                return RecognizedLine(text: text, bounds: bounds, words: words)
            }
            controller.useTextLines(lines)
            controller.switchMode(to: .text)
            controller.mouseMoved(to: CGPoint(x: 300, y: 452))
        }
        // The frozen picture is a layer in the app; here it is drawn below the (transparent) marks by hand.
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = context
        NSImage(cgImage: sample, size: size).draw(in: NSRect(origin: .zero, size: size))
        context.cgContext.translateBy(x: 0, y: size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func settingsTab(_ index: Int, settings: SettingsStore) -> NSBitmapImageRep? {
        let root = SettingsTabSnapshot(store: settings, status: SystemStatus(), tab: index)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 600)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return capture(hosting)
    }

    static func capture(_ view: NSView) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func write(_ rep: NSBitmapImageRep?, to url: URL) throws {
        guard let data = rep?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        try data.write(to: url)
        print("Wrote \(url.path)")
    }

    /// A made-up window with text lines, so effects like the highlighter and pixelate have something to show.
    static func sampleImage(width: Int, height: Int) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let w = CGFloat(width), h = CGFloat(height)
        NSGradient(starting: NSColor(srgbRed: 0.85, green: 0.9, blue: 0.97, alpha: 1),
                   ending: NSColor(srgbRed: 0.7, green: 0.78, blue: 0.92, alpha: 1))?
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
        let card = NSRect(x: 50, y: 60, width: 1140, height: 690)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
        NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: card.minX, y: card.maxY - 44, width: card.width, height: 44)).fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: card.minX + 18 + CGFloat(i) * 22, y: card.maxY - 29, width: 13, height: 13)).fill()
        }
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.black]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.darkGray]
        NSAttributedString(string: "Quarterly report", attributes: title).draw(at: NSPoint(x: 110, y: h - 140))
        NSColor(srgbRed: 0.36, green: 0.62, blue: 0.95, alpha: 1).setFill()
        for (i, value) in [0.5, 0.8, 0.35, 0.95, 0.6, 0.75].enumerated() {
            NSBezierPath(rect: NSRect(x: 120 + CGFloat(i) * 70, y: h - 340, width: 46, height: 160 * value)).fill()
        }
        let lines = ["Revenue grew in every region this quarter.", "Contact: support@example.com  Order 4711-0815",
                     "Next review: Thursday at 10:00"]
        for (i, line) in lines.enumerated() {
            NSAttributedString(string: line, attributes: body).draw(at: NSPoint(x: 100, y: h - 430 - CGFloat(i) * 30))
        }
        NSColor(srgbRed: 0.98, green: 0.6, blue: 0.2, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 880, y: h - 320, width: 220, height: 160)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}

/// One tab of the settings, for the snapshots (a TabView only draws its selected tab).
private struct SettingsTabSnapshot: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus
    let tab: Int

    var body: some View {
        SettingsView(store: store, status: status, initialTab: tab)
    }
}
