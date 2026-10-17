// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ScreenCaptureKit

private let log = Log("Capture")

/// HDR screens (upstream 1.4: `Greenshot.Base/Native/HdrContent.cs`, `HdrToneMapper.cs`): while a display shows HDR
/// content (its EDR headroom is above 1), it is also taken in HDR (macOS 15 and later, Apple silicon), and when more
/// than a few of its pixels are brighter than SDR white (by luminance) they are tone mapped into the 8-bit screenshot
/// instead of being cut off (`CaptureHDR`). Otherwise the SDR picture is used as always, so SDR content, wide gamut
/// colours included, keeps its exact colours.
extension ScreenCapturer {
    /// The current EDR headroom of the display, when HDR captures are on, possible here and the display shows HDR
    /// content now; nil otherwise.
    static func hdrHeadroom(of displayID: CGDirectDisplayID, enabled: Bool) -> CGFloat? {
        guard enabled, supportsHDR else { return nil }
        let headroom = NSScreen.screens.first { $0.displayID == displayID }?.maximumExtendedDynamicRangeColorComponentValue ?? 1
        return headroom > 1 ? headroom : nil
    }

    /// The headroom of the display that holds most of `frame` (Quartz global points), see `hdrHeadroom(of:enabled:)`.
    static func hdrHeadroom(of frame: CGRect, enabled: Bool) -> CGFloat? {
        guard enabled, supportsHDR else { return nil }
        let displays = NSScreen.screens.map { ($0.displayID, CGDisplayBounds($0.displayID).intersection(frame)) }
        guard let best = displays.filter({ !$0.1.isNull }).max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height })
        else { return nil }
        return hdrHeadroom(of: best.0, enabled: enabled)
    }

    /// ScreenCaptureKit takes HDR pictures from macOS 15 on, and only on Apple silicon (SCStream.h).
    static var supportsHDR: Bool {
        #if arch(arm64)
        if #available(macOS 15, *) { return true }
        #endif
        return false
    }

    /// A picture in HDR for the local display, nil when it can't be taken (the SDR picture is used then).
    static func hdrPicture(_ filter: SCContentFilter, scale: CGFloat, showsCursor: Bool, ignoresShadow: Bool?) async -> CGImage? {
        guard #available(macOS 15, *) else { return nil }
        let configuration = SCStreamConfiguration(preset: .captureHDRScreenshotLocalDisplay)
        configure(configuration, filter: filter, scale: scale, showsCursor: showsCursor, ignoresShadow: ignoresShadow)
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            log.warn("The HDR picture could not be taken, the SDR one is used", error: error)
            return nil
        }
    }

    /// The tone mapped `hdr` pictures when the first has HDR content and every one was taken in the size of its SDR
    /// picture; else `sdr`.
    static func preferringHDR(sdr: [CGImage], hdr: [CGImage?], headroom: CGFloat, name: String) async -> [CGImage] {
        let taken = hdr.compactMap { $0 }
        guard taken.count == sdr.count,
              zip(sdr, taken).allSatisfy({ $0.width == $1.width && $0.height == $1.height }) else { return sdr }
        let peak = Float(headroom)
        let result = await Task.detached(priority: .userInitiated) {
            CaptureHDR.toneMapped(taken, displayPeak: peak)
        }.value
        guard let result else {
            log.debug("No HDR content or only a few highlights on \(name) (headroom \(headroom)), the SDR picture is used")
            return sdr
        }
        let measurement = result.measurement
        log.info("HDR content on \(name): peak \(measurement.peak), \(Int(measurement.highlightShare * 100)) % highlights, "
                 + "white level \(result.whiteLevel), headroom \(headroom): tone mapped")
        return result.images
    }
}
