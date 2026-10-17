// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// A capture from the browser extension, after its image was checked (upstream `BrowserExtensionIpcExtension`
/// `HandleImportCaptureAsync` and `CaptureHelper.ImportExtensionCapture`): the page's address and browser become the
/// capture's `${url}` and `${browser}`, then a recipe with an Extension trigger (or the built-in "Capture from browser
/// extension") takes it; without recipes the destination picker asks where it goes, as upstream's built-in recipe does
/// (Source Extension → DynamicDestination "Export Browser Capture").
@MainActor
enum BrowserCaptureImport {
    private static let log = Log("Browser")

    static func deliver(_ image: CGImage, request: BrowserImportRequest, app: AppDelegate) {
        let date = Date()
        let scale = request.scale(pixelWidth: image.width)
        CaptureMetadataStore.shared.record(request.metadata, forCaptureAt: date)
        if !request.url.isEmpty {
            BrowserContext.shared.update(url: request.url, title: request.title)
        }

        var payload = RecipePayload(image: image, scale: scale, title: request.title, captureDate: date)
        payload.sourceType = "Extension"
        payload.metadata = request.metadata.mapValues { JSONValue.string($0) }
        let capture = Capture(image: image, scale: scale, title: request.title, date: date)
        // After the acknowledgement went out: the picker's menu waits for the user
        DispatchQueue.main.async {
            if RecipeRuntime.shared?.importExtensionCapture(payload, browser: request.browser) != nil {
                log.info("Browser capture handed to a recipe (\(request.browser ?? "unknown browser")).")
                return
            }
            log.info("Browser capture imported (\(request.browser ?? "unknown browser")); asking where it goes.")
            app.output.perform(.destination(.picker), with: capture)
        }
    }
}
