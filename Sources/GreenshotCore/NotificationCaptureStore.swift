// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The captures that notifications offer again after a click, also after a restart: port of upstream
/// `Greenshot/Notifications/NotificationCaptures.cs`. Each is a PNG named by a UUID v7, the id the notification carries.
/// Upstream keeps a `.greenshot` file; here a capture is already one flat image, so a PNG keeps all of it.
public struct NotificationCaptureStore: Sendable {
    /// How long a notification and its capture live (upstream: the toasts expire after an hour).
    public static let lifetime: TimeInterval = 60 * 60

    /// `~/Library/Caches/<bundle id>/Notifications`.
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The store in the caches folder of the app with this bundle id.
    public static func inCaches(bundleIdentifier: String, fileManager: FileManager = .default) -> NotificationCaptureStore? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return NotificationCaptureStore(folder: caches.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Notifications", isDirectory: true))
    }

    /// The id as a file name: the canonical (lower case) form of a UUID, nil for anything else. Only an id may name a
    /// file, as it comes back from the notification (upstream checks `Guid.TryParseExact`).
    public static func canonicalId(_ id: String?) -> String? {
        guard let id, id.count == 36, let uuid = UUID(uuidString: id) else { return nil }
        return uuid.uuidString.lowercased()
    }

    /// The kept capture.
    public func captureURL(_ id: String) -> URL? {
        Self.canonicalId(id).map { folder.appendingPathComponent($0 + ".png") }
    }

    /// The image a notification shows. macOS moves this file into its own store when the notification is posted, so it
    /// is never the kept capture itself.
    public func attachmentURL(_ id: String) -> URL? {
        Self.canonicalId(id).map { folder.appendingPathComponent($0 + "-attachment.png") }
    }

    /// The names of the files in the store that are older than `lifetime` (upstream `RemoveUnused`: a notification
    /// lives an hour; a younger capture may belong to a click that is on its way).
    public static func expiredFiles(_ files: [(name: String, modified: Date)], now: Date = Date(),
                                    lifetime: TimeInterval = lifetime) -> [String] {
        files.filter { now.timeIntervalSince($0.modified) > lifetime }.map(\.name)
    }

    /// A new id: a UUID version 7 (RFC 9562), the time in milliseconds followed by random bits, so the files sort by
    /// when they were made (upstream `CreateId`).
    public static func newId(now: Date = Date()) -> String {
        var generator = SystemRandomNumberGenerator()
        return newId(now: now, using: &generator)
    }

    public static func newId<Generator: RandomNumberGenerator>(now: Date, using generator: inout Generator) -> String {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let milliseconds = UInt64(max(0, (now.timeIntervalSince1970 * 1000).rounded(.down)))
        for index in 0..<6 {
            let shift = UInt64(40 - index * 8)
            bytes[index] = UInt8(truncatingIfNeeded: milliseconds >> shift)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        return parts.joined(separator: "-")
    }
}

/// The picture of the capture in a notification (upstream `NotificationCaptures.WriteThumbnailAsync`: at most 364×180,
/// the largest a Windows toast shows unscaled). Twice that here, for Retina screens.
public enum NotificationThumbnail {
    public static let maxPixelWidth = 728
    public static let maxPixelHeight = 360

    /// `size` scaled down to fit, aspect ratio kept, never enlarged, at least 1×1.
    public static func size(for size: CGSize, maxWidth: Int = maxPixelWidth, maxHeight: Int = maxPixelHeight) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let widthRatio = CGFloat(maxWidth) / size.width
        let heightRatio = CGFloat(maxHeight) / size.height
        let ratio = min(1, widthRatio, heightRatio)
        let width = max(1, (size.width * ratio).rounded())
        let height = max(1, (size.height * ratio).rounded())
        return CGSize(width: width, height: height)
    }

    /// The thumbnail of `image` (sRGB, with alpha).
    public static func make(_ image: CGImage) -> CGImage? {
        let target = size(for: CGSize(width: image.width, height: image.height))
        let width = Int(target.width)
        let height = Int(target.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
