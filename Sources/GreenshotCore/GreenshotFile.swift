// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// `.greenshot` files: a screenshot whose elements can be edited again (upstream
/// `Greenshot.Editor/FileFormatHandlers/GreenshotFileFormatHandler.cs`). The layout is upstream's:
///
///     [PNG of the image without elements][the elements][Int64 length of the elements, little endian]["GreenshotXX.YY"]
///
/// Greenshot for Windows writes the elements with .NET's BinaryFormatter and ends with its version ("Greenshot01.03");
/// they are read by `GreenshotLegacyImport`. This app writes them as JSON and ends with its own marker,
/// `macMarker`. As the file starts with a PNG, image viewers show the image, and Greenshot for Windows opens the image
/// without the elements (its `Surface.LoadElementsFromStream` logs the elements it can't read and goes on).
public enum GreenshotFile {
    public static let fileExtension = "greenshot"
    /// The type declared in the app's Info.plist.
    public static let typeIdentifier = "io.github.greenshot-mac.greenshot"
    /// The end of the files this app writes: 14 characters like upstream's "GreenshotXX.YY", and starting with
    /// "Greenshot" so that Greenshot for Windows takes it for its own file and opens the image.
    public static let macMarker = "GreenshotMac01"
    static let markerLength = 14
    static let trailerLength = 8 + markerLength
    /// Bigger files are not read: a screenshot with its elements is far smaller, and the file is read into memory.
    public static let maxFileBytes = 512 * 1024 * 1024

    /// Which app wrote a file.
    public enum Origin: Equatable, Sendable {
        /// This app.
        case mac
        /// Greenshot for Windows, with the marker that ends the file, e.g. "Greenshot01.03".
        case windows(marker: String)
        /// An image that only has the name: no `.greenshot` ending (upstream refuses these; here the image opens).
        case imageOnly
    }

    /// What a file kept for the next start of the app (see `EditorSessionStore`) knows about its editor.
    public struct Session: Codable, Equatable, Sendable {
        public enum Reason: String, Codable, Sendable {
            /// Written while the editor was open, in case the app doesn't get to quit (a crash, a forced quit).
            case autosave
            /// Written when the app quit for a logout, restart or shut down, or with "Close windows when quitting an
            /// application" off.
            case quit
        }

        public var reason: Reason
        /// The file the editor showed (opened from or saved to), so Save goes there again.
        public var originalFile: String?
        /// Save must not write over `originalFile` (see `EditorDocument.savesToNewFile`).
        public var savesToNewFile: Bool

        public init(reason: Reason, originalFile: String? = nil, savesToNewFile: Bool = false) {
            self.reason = reason
            self.originalFile = originalFile
            self.savesToNewFile = savesToNewFile
        }

        enum CodingKeys: String, CodingKey {
            case reason, originalFile, savesToNewFile
            /// The name of `savesToNewFile` in the first files, which set it only for files of Greenshot for Windows.
            case isWindowsGreenshotFile
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            reason = try c.decode(Reason.self, forKey: .reason)
            originalFile = try c.decodeIfPresent(String.self, forKey: .originalFile)
            if let saves = try c.decodeIfPresent(Bool.self, forKey: .savesToNewFile) {
                savesToNewFile = saves
            } else {
                savesToNewFile = try c.decodeIfPresent(Bool.self, forKey: .isWindowsGreenshotFile) ?? false
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(reason, forKey: .reason)
            try c.encodeIfPresent(originalFile, forKey: .originalFile)
            try c.encode(savesToNewFile, forKey: .savesToNewFile)
        }
    }

    /// What a `.greenshot` file holds: what is written, and what was read.
    /// Sendable: the image is immutable and the rest are values.
    public struct Contents: @unchecked Sendable {
        /// The image without the elements (upstream `Surface.Image`).
        public var image: CGImage
        /// Pixels per point.
        public var scale: CGFloat
        public var elements: [Annotation]
        public var counterStart: Int
        public var title: String?
        public var captureDate: Date?
        /// Only in the files kept for the next start; a file the user saves never has a local path in it.
        public var session: Session?
        /// Who wrote the file (for files that were read).
        public var origin: Origin
        /// The kinds of elements in the file that can't be shown here (e.g. "SVG", "Unknown element"), in the order
        /// they came; empty when every element was read.
        public var unreadable: [String]
        /// The file has elements, but they could not be read at all.
        public var elementsFailed: Bool

        public init(image: CGImage, scale: CGFloat, elements: [Annotation] = [], counterStart: Int = 1, title: String? = nil,
                    captureDate: Date? = nil, session: Session? = nil, origin: Origin = .mac, unreadable: [String] = [],
                    elementsFailed: Bool = false) {
            self.image = image
            self.scale = scale
            self.elements = elements
            self.counterStart = counterStart
            self.title = title
            self.captureDate = captureDate
            self.session = session
            self.origin = origin
            self.unreadable = unreadable
            self.elementsFailed = elementsFailed
        }

        /// The document as it is saved: its image without the elements, and the elements.
        public init(of document: EditorDocument, session: Session? = nil) {
            self.init(image: document.baseImage, scale: document.scale, elements: document.annotations,
                      counterStart: document.counterStart, title: document.title, captureDate: document.captureDate,
                      session: session)
        }

        /// What the editor says after opening the file; nil when there is nothing to say.
        public var openMessage: String? {
            if elementsFailed { return "The elements of this file could not be read, the image is shown without them." }
            if let message = GreenshotFile.unreadableMessage(unreadable) { return message }
            if case .windows = origin {
                return "A file of Greenshot for Windows: Save asks for a new file, so this one stays as it is."
            }
            return nil
        }

        /// Writes the file to `url`, creating missing folders on the way.
        public func write(to url: URL) throws {
            let data = try encoded()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }

        /// The file this app writes (upstream `GreenshotFileFormatHandler.TrySaveToStream`).
        public func encoded() throws -> Data {
            var data = try ImageExporter.data(for: image, format: .png, scale: scale)
            let payload = GreenshotFilePayload(scale: scale, counterStart: counterStart, title: title, captureDate: captureDate,
                                               session: session, elements: elements.map { LossyAnnotation(value: $0) })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let block = try encoder.encode(payload)
            data.append(block)
            var length = Int64(block.count).littleEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(contentsOf: Array(macMarker.utf8))
            return data
        }
    }

    /// The extension of the element files of Greenshot for Windows (its "Save objects to file", upstream
    /// `ImageEditorForm.SaveElementsToolStripMenuItemClick`: the BinaryFormatter stream of the elements alone).
    public static let templateExtension = "gst"

    /// Whether `url` names a `.greenshot` file.
    public static func isGreenshotFile(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(fileExtension) == .orderedSame
    }

    /// The elements of a `.gst` file of Greenshot for Windows, for an image with `scale` pixels per point, and the kinds
    /// of the elements that can't be shown.
    public static func readTemplate(_ data: Data, scale: CGFloat) throws -> (elements: [Annotation], unreadable: [String]) {
        guard data.count <= maxFileBytes else { throw NRBFError.badLength }
        let result = try GreenshotLegacyImport.read(payload: data, scale: scale)
        return Annotation.withinLimits(result.elements, unreadable: result.unreadable)
    }

    /// The editor's message about elements that were left out, e.g. "2 elements can't be shown here: SVG picture,
    /// Payload."; nil when none were.
    public static func unreadableMessage(_ unreadable: [String]) -> String? {
        guard !unreadable.isEmpty else { return nil }
        var kinds: [String] = []
        for kind in unreadable where !kinds.contains(kind) { kinds.append(kind) }
        let count = unreadable.count == 1 ? "1 element" : "\(unreadable.count) elements"
        return "\(count) can't be shown here: \(kinds.joined(separator: ", "))."
    }

    /// Reads a `.greenshot` file; nil when it is too big or has no image.
    public static func read(contentsOf url: URL) -> Contents? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxFileBytes, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            log.warn("\(url.lastPathComponent) is too big or could not be read (\(size) bytes)")
            return nil
        }
        return read(data)
    }

    /// Reads a `.greenshot` file of this app or of Greenshot for Windows (upstream `ImageIO.LoadGreenshotSurface`); an
    /// image without the `.greenshot` ending opens as an image. Nil when there is no image.
    public static func read(_ data: Data) -> Contents? {
        guard data.count <= maxFileBytes else { return nil }
        let data = data.startIndex == 0 ? data : Data(data)
        guard let trailer = GreenshotFileTrailer.locate(in: data) else {
            guard let loaded = ImageFileLoader.load(data: data) else { return nil }
            return Contents(image: loaded.image, scale: loaded.scale, origin: .imageOnly)
        }
        guard let loaded = ImageFileLoader.load(data: data.subdata(in: 0..<trailer.elements.lowerBound)) else { return nil }
        let block = data.subdata(in: trailer.elements)
        if trailer.marker == macMarker {
            return readMacElements(block, image: loaded.image, scale: loaded.scale)
        }
        var contents = Contents(image: loaded.image, scale: loaded.scale, origin: .windows(marker: trailer.marker))
        do {
            let imported = try GreenshotLegacyImport.read(payload: block, scale: loaded.scale)
            (contents.elements, contents.unreadable) = Annotation.withinLimits(imported.elements, unreadable: imported.unreadable)
            contents.counterStart = imported.counterStart
        } catch {
            // Like upstream: the image opens, the elements are left out.
            log.error("The elements of a Greenshot for Windows file (\(trailer.marker)) could not be read", error: error)
            contents.elementsFailed = true
        }
        return contents
    }

    private static func readMacElements(_ block: Data, image: CGImage, scale: CGFloat) -> Contents {
        guard let payload = try? JSONDecoder().decode(GreenshotFilePayload.self, from: block),
              payload.scale.isFinite, payload.scale > 0 else {
            log.error("The elements of a .greenshot file could not be read")
            return Contents(image: image, scale: scale, origin: .mac, elementsFailed: true)
        }
        let decoded = payload.elements.compactMap(\.value)
        let skipped = payload.elements.count - decoded.count
        let (elements, unreadable) = Annotation.withinLimits(decoded, unreadable: Array(repeating: "Element of a newer version", count: skipped))
        return Contents(image: image, scale: min(max(payload.scale, 1), 8), elements: elements.map { $0.withNewID() },
                        counterStart: min(max(payload.counterStart, 0), 999_999), title: payload.title,
                        captureDate: payload.captureDate, session: payload.session, origin: .mac,
                        unreadable: unreadable)
    }

    private static let log = Log("Greenshot file")
}

/// Where the parts of a `.greenshot` file are: the 14 character marker at the end, before it the length of the
/// elements, before that the elements; the image is everything in front of them.
struct GreenshotFileTrailer: Equatable {
    var marker: String
    var elements: Range<Int>

    /// Nil when `data` (starting at index 0) doesn't end like a `.greenshot` file (upstream `LoadGreenshotSurface`
    /// checks for "Greenshot" too), or the length doesn't fit in the file.
    static func locate(in data: Data) -> GreenshotFileTrailer? {
        let count = data.count
        guard count >= GreenshotFile.trailerLength else { return nil }
        let markerStart = count - GreenshotFile.markerLength
        guard let marker = String(bytes: data[markerStart..<count], encoding: .ascii), marker.hasPrefix("Greenshot") else {
            return nil
        }
        let lengthStart = markerStart - 8
        var length: Int64 = 0
        for (offset, byte) in data[lengthStart..<markerStart].enumerated() {
            length |= Int64(byte) << (8 * Int64(offset))
        }
        guard length >= 0, length <= Int64(lengthStart) else { return nil }
        return GreenshotFileTrailer(marker: marker, elements: (lengthStart - Int(length))..<lengthStart)
    }
}

/// The JSON of the elements in the files this app writes.
struct GreenshotFilePayload: Codable {
    var format = "greenshot-mac"
    var version = 1
    var scale: CGFloat
    var counterStart: Int
    var title: String?
    var captureDate: Date?
    var session: GreenshotFile.Session?
    var elements: [LossyAnnotation]
}

/// An element that is left out when it can't be read (e.g. a kind of a newer version), instead of failing the file.
struct LossyAnnotation: Codable {
    var value: Annotation?

    init(value: Annotation?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        value = try? Annotation(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try value?.encode(to: encoder)
    }
}
