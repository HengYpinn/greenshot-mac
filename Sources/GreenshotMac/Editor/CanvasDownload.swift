// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import GreenshotCore

/// Downloads the pictures of links dropped on the canvas and of `<img>` tags in pasted HTML (upstream
/// `NetworkHelper.DownloadImageAsDrawableContainerAsync`). The editor keeps working meanwhile.
enum CanvasDownload {
    /// The first of `urls` that downloads as a picture (with its pixels per point) or an SVG.
    static func firstPicture(from urls: [URL]) async -> ElementPicture? {
        for url in urls.prefix(ImageDownload.maxURLs) {
            if let picture = await picture(from: url) { return picture }
        }
        return nil
    }

    /// The picture or SVG at `url` (http, https or data); nil when it can't be downloaded or is neither. Downloads stay
    /// within the limits of `ImageDownload`; a data URL is already in memory. An SVG stays an SVG element (upstream
    /// `DownloadImageAsDrawableContainerAsync` asks the file format handlers, `SvgFileFormatHandler` among them).
    static func picture(from url: URL) async -> ElementPicture? {
        let data: Data?
        if url.scheme?.lowercased() == "data" {
            data = try? Data(contentsOf: url)
        } else {
            data = await ImageDownload.data(from: url)
        }
        return data.flatMap(ElementPictures.content(of:))
    }
}
