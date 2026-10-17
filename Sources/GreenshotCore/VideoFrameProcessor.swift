// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// Turns the frames of the screen into frames of the video: grayscale (upstream `VideoColorMode.Grayscale`, which
/// upstream's session doesn't apply) and a window whose size changed placed into the video's fixed size (upstream
/// `WindowResizeBehavior`). A frame that needs neither goes through untouched. Used on one queue at a time.
public final class VideoFrameProcessor: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let colorMode: VideoColorMode
    public let behavior: WindowResizeBehavior
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var ownPool: CVPixelBufferPool?

    public init(width: Int, height: Int, colorMode: VideoColorMode, behavior: WindowResizeBehavior) {
        self.width = width
        self.height = height
        self.colorMode = colorMode
        self.behavior = behavior
    }

    /// The frame to encode. `contentRect` is the part of `buffer` with the picture, in pixels from its top left (nil:
    /// all of it). A new frame comes from `pool` (the writer's) or a pool of its own; nil when none could be made.
    public func process(_ buffer: CVPixelBuffer, contentRect: CGRect? = nil, pool: CVPixelBufferPool? = nil) -> CVPixelBuffer? {
        let bufferWidth = CVPixelBufferGetWidth(buffer)
        let bufferHeight = CVPixelBufferGetHeight(buffer)
        let full = CGRect(x: 0, y: 0, width: bufferWidth, height: bufferHeight)
        let content = (contentRect ?? full).integral.intersection(full)
        let coversBuffer = content.width >= CGFloat(bufferWidth - 1) && content.height >= CGFloat(bufferHeight - 1)
        let sameSize = bufferWidth == width && bufferHeight == height
        if colorMode == .fullColor && sameSize && coversBuffer { return buffer }
        guard !content.isEmpty, let output = makeBuffer(pool: pool) else { return nil }

        // Core Image's origin is the bottom left.
        let flipped = CGRect(x: content.minX, y: CGFloat(bufferHeight) - content.maxY, width: content.width, height: content.height)
        var image = CIImage(cvPixelBuffer: buffer).cropped(to: flipped)
            .transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        if !(sameSize && coversBuffer) {
            let place = RecordingGeometry.placement(content: content.size, canvas: canvas.size, behavior: behavior)
            let scaleX = place.width / content.width
            let scaleY = place.height / content.height
            image = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .transformed(by: CGAffineTransform(translationX: place.minX, y: canvas.height - place.maxY))
            image = image.composited(over: CIImage(color: .black).cropped(to: canvas))
        }
        if colorMode == .grayscale {
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        }
        context.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: colorSpace)
        return output
    }

    private func makeBuffer(pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var output: CVPixelBuffer?
        if let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess { return output }
        if ownPool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &ownPool)
        }
        guard let ownPool, CVPixelBufferPoolCreatePixelBuffer(nil, ownPool, &output) == kCVReturnSuccess else { return nil }
        return output
    }
}
