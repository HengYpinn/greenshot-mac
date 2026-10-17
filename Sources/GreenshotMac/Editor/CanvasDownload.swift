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
    /// The first of `urls` that downloads as a picture, with its pixels per point.
    static func firstPicture(from urls: [URL]) async -> (image: CGImage, scale: CGFloat)? {
        for url in urls {
            if let picture = await picture(from: url) { return picture }
        }
        return nil
    }

    /// The picture at `url` (http, https or data); nil when it can't be downloaded or isn't a picture.
    static func picture(from url: URL) async -> (image: CGImage, scale: CGFloat)? {
        guard ["http", "https", "data"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return ElementPictures.load(data: data)
    }
}
