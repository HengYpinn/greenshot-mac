// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// The `.greenshot` files this app writes: upstream's layout (PNG, elements, length, marker) with JSON elements.
struct GreenshotFileTests {
    static let background = TestImage.make(width: 40, height: 30) { x, _ in x < 20 ? .red : .blue }

    static func sampleElements() throws -> [Annotation] {
        var text = Annotation(kind: .text, start: CGPoint(x: 2, y: 3), end: CGPoint(x: 30, y: 20), text: "Hello")
        text.style.fontFamily = "Helvetica"
        var bubble = Annotation(kind: .speechBubble, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 25, y: 15), text: "Hi",
                                tail: CGPoint(x: 1, y: 29))
        bubble.style.fillColor = .yellow
        let picture = try #require(Annotation.picture(TestImage.make(width: 4, height: 4) { _, _ in .black }, pictureScale: 1,
                                                       at: CGPoint(x: 10, y: 10), documentScale: 2))
        var mark = Annotation(kind: .cutMark, start: CGPoint(x: 0, y: 10), end: CGPoint(x: 40, y: 14))
        mark.seed = 42
        mark.verticalCut = false
        return [
            Annotation(kind: .rectangle, start: CGPoint(x: 1, y: 1), end: CGPoint(x: 10, y: 8)),
            Annotation(kind: .freehand, start: .zero, end: .zero, points: [CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 9)]),
            text, bubble, picture, mark,
            Annotation(kind: .counter, start: CGPoint(x: 30, y: 2), end: CGPoint(x: 38, y: 10)),
        ]
    }

    static func written(session: GreenshotFile.Session? = nil) throws -> Data {
        let contents = GreenshotFile.Contents(image: background, scale: 2, elements: try sampleElements(), counterStart: 3,
                                              title: "Safari", captureDate: Date(timeIntervalSinceReferenceDate: 1000),
                                              session: session)
        return try contents.encoded()
    }

    /// The elements without their ids, which change on reading.
    static func withoutIDs(_ elements: [Annotation]) -> [Annotation] {
        elements.map { element in
            var copy = element
            copy.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            return copy
        }
    }

    @Test func roundTrip() throws {
        let contents = try #require(GreenshotFile.read(try Self.written()))
        #expect(contents.origin == .mac)
        #expect(contents.image.width == 40)
        #expect(contents.image.height == 30)
        #expect(contents.scale == 2)
        #expect(contents.counterStart == 3)
        #expect(contents.title == "Safari")
        #expect(contents.captureDate == Date(timeIntervalSinceReferenceDate: 1000))
        #expect(contents.session == nil)
        #expect(contents.unreadable.isEmpty)
        #expect(Self.withoutIDs(contents.elements) == Self.withoutIDs(try Self.sampleElements()))
    }

    @Test func readElementsGetNewIDs() throws {
        let originals = Set(try Self.sampleElements().map(\.id))
        let contents = try #require(GreenshotFile.read(try Self.written()))
        #expect(originals.isDisjoint(with: contents.elements.map(\.id)))
        #expect(Set(contents.elements.map(\.id)).count == contents.elements.count)
    }

    @Test func endsLikeUpstreamFiles() throws {
        let data = try Self.written()
        #expect(String(decoding: data.suffix(14), as: UTF8.self) == "GreenshotMac01")
        let trailer = try #require(GreenshotFileTrailer.locate(in: data))
        let block = data.subdata(in: trailer.elements)
        #expect(block.first == UInt8(ascii: "{"))
        #expect(trailer.elements.upperBound == data.count - 22)
        // Upstream: GreenshotFileFormatHandler.LoadSurface reads the image from the start of the file.
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func theImageOpensAnywhere() throws {
        let loaded = try #require(ImageFileLoader.load(data: try Self.written()))
        #expect(loaded.image.width == 40)
        #expect(loaded.scale == 2)
    }

    @Test func sessionIsKept() throws {
        let session = GreenshotFile.Session(reason: .quit, originalFile: "/tmp/x.png", savesToNewFile: true)
        let contents = try #require(GreenshotFile.read(try Self.written(session: session)))
        #expect(contents.session == session)
    }

    /// A file of this app with an element of a kind this version doesn't know.
    static func newerVersionFile() throws -> Data {
        let data = try written()
        let trailer = try #require(GreenshotFileTrailer.locate(in: data))
        let json = String(decoding: data.subdata(in: trailer.elements), as: UTF8.self)
        let changed = Data(json.replacingOccurrences(of: "\"kind\":\"rectangle\"", with: "\"kind\":\"hologram\"").utf8)
        var file = data.subdata(in: 0..<trailer.elements.lowerBound)
        file.append(changed)
        var length = Int64(changed.count).littleEndian
        withUnsafeBytes(of: &length) { file.append(contentsOf: $0) }
        file.append(contentsOf: Array("GreenshotMac01".utf8))
        return file
    }

    @Test func elementOfANewerVersionIsLeftOut() throws {
        let contents = try #require(GreenshotFile.read(try Self.newerVersionFile()))
        #expect(contents.elements.count == (try Self.sampleElements()).count - 1)
        #expect(contents.unreadable.count == 1)
        #expect(contents.savesToNewFile)
    }

    @Test func fileWithUnreadElementsIsNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GreenshotFileTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Newer.greenshot")
        let original = try Self.newerVersionFile()
        try original.write(to: url)
        let contents = try #require(GreenshotFile.read(contentsOf: url))
        let document = EditorDocument(opening: contents, from: url)
        #expect(document.savesToNewFile)
        document.change { document.add(Annotation(kind: .ellipse, start: .zero, end: CGPoint(x: 9, y: 9))) }
        // Save asks for a new file: nothing is written over the one with the element this version can't read.
        let savedInPlace = try GreenshotFile.saveInPlace(document)
        let bytes = try Data(contentsOf: url)
        #expect(!savedInPlace)
        #expect(bytes == original)
        #expect(contents.openStatus?.contains("Save asks for a new file") == true)
    }

    @Test func readableFileIsSavedInPlace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GreenshotFileTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Mine.greenshot")
        try Self.written().write(to: url)
        let contents = try #require(GreenshotFile.read(contentsOf: url))
        #expect(!contents.savesToNewFile)
        #expect(contents.openStatus == nil)
        let document = EditorDocument(opening: contents, from: url)
        document.change { document.add(Annotation(kind: .ellipse, start: .zero, end: CGPoint(x: 9, y: 9))) }
        let savedInPlace = try GreenshotFile.saveInPlace(document)
        #expect(savedInPlace)
        let saved = try #require(GreenshotFile.read(contentsOf: url))
        #expect(saved.elements.count == contents.elements.count + 1)
    }

    @Test func restoredEditorStaysCareful() throws {
        let session = GreenshotFile.Session(reason: .autosave, originalFile: "/tmp/Newer.greenshot", savesToNewFile: true)
        let contents = try #require(GreenshotFile.read(try Self.written(session: session)))
        let document = EditorDocument(restoring: contents) { _ in true }
        #expect(document.savesToNewFile)
        #expect(document.isModified)
        #expect(document.fileURL?.path == "/tmp/Newer.greenshot")
        let gone = EditorDocument(restoring: contents) { _ in false }
        #expect(gone.fileURL == nil)
    }

    @Test func sessionOfTheFirstFilesStillReads() throws {
        let json = Data(#"{"reason":"quit","originalFile":"/tmp/a.greenshot","isWindowsGreenshotFile":true}"#.utf8)
        let session = try JSONDecoder().decode(GreenshotFile.Session.self, from: json)
        #expect(session.savesToNewFile)
        #expect(session.originalFile == "/tmp/a.greenshot")
    }

    @Test func plainImageWithTheName() throws {
        let png = try ImageExporter.data(for: Self.background, format: .png)
        let contents = try #require(GreenshotFile.read(png))
        #expect(contents.origin == .imageOnly)
        #expect(contents.elements.isEmpty)
        #expect(contents.image.width == 40)
    }

    @Test func brokenFiles() throws {
        let data = try Self.written()
        #expect(GreenshotFile.read(Data()) == nil)
        #expect(GreenshotFile.read(Data(repeating: 7, count: 100)) == nil)
        // The end of the file cut off: no marker, and the rest is no image.
        #expect(GreenshotFile.read(data.suffix(200)) == nil)
    }

    @Test func lengthLargerThanTheFileIsNoTrailer() {
        var data = Data(repeating: 0, count: 10)
        var length = Int64.max.littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array("Greenshot01.03".utf8))
        #expect(GreenshotFileTrailer.locate(in: data) == nil)
        var negative = Data(repeating: 0, count: 10)
        var minus = Int64(-1).littleEndian
        withUnsafeBytes(of: &minus) { negative.append(contentsOf: $0) }
        negative.append(contentsOf: Array("Greenshot01.03".utf8))
        #expect(GreenshotFileTrailer.locate(in: negative) == nil)
    }

    @Test func otherMarkerIsNoTrailer() throws {
        var data = try Self.written()
        data.replaceSubrange((data.count - 14)..<data.count, with: Array("NotGreenshot01".utf8))
        #expect(GreenshotFileTrailer.locate(in: data) == nil)
    }

    @Test func brokenElementsKeepTheImage() throws {
        let data = try Self.written()
        let trailer = try #require(GreenshotFileTrailer.locate(in: data))
        var broken = data
        broken.replaceSubrange(trailer.elements.lowerBound..<(trailer.elements.lowerBound + 1), with: [UInt8(ascii: "x")])
        let contents = try #require(GreenshotFile.read(broken))
        #expect(contents.elementsFailed)
        #expect(contents.elements.isEmpty)
        #expect(contents.image.width == 40)
    }

    @Test func documentContents() throws {
        let document = EditorDocument(image: Self.background, scale: 2, title: "Doc")
        document.counterStart = 5
        document.change { document.add(Annotation(kind: .ellipse, start: .zero, end: CGPoint(x: 9, y: 9))) }
        let contents = GreenshotFile.Contents(of: document)
        #expect(contents.elements.map(\.kind) == [.ellipse])
        #expect(contents.counterStart == 5)
        #expect(contents.title == "Doc")
        #expect(contents.image === document.baseImage)
    }
}

/// What the editor document adds for opened files and the autosave.
struct EditorDocumentOpenedTests {
    @Test func openedElementsAreNoChange() {
        let document = EditorDocument(image: GreenshotFileTests.background, scale: 1, title: "x", isModified: false)
        let before = document.changeCount
        document.addOpened([Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 5, y: 5))])
        #expect(document.annotations.count == 1)
        #expect(!document.canUndo)
        #expect(!document.isModified)
        #expect(document.changeCount > before)
    }

    @Test func changeCountGrowsWithEveryChange() {
        let document = EditorDocument(image: GreenshotFileTests.background, scale: 1, title: "x")
        var counts = [document.changeCount]
        document.change { document.add(Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 5, y: 5))) }
        counts.append(document.changeCount)
        document.undo()
        counts.append(document.changeCount)
        document.redo()
        counts.append(document.changeCount)
        document.change {} // nothing changed: no step
        counts.append(document.changeCount)
        document.reset(image: GreenshotFileTests.background, scale: 1, title: "y")
        counts.append(document.changeCount)
        #expect(counts == [0, 1, 2, 3, 3, 4])
    }

    @Test func newScreenshotSavesWhereItLikes() {
        let document = EditorDocument(image: GreenshotFileTests.background, scale: 1, title: "x")
        document.savesToNewFile = true
        document.reset(image: GreenshotFileTests.background, scale: 1, title: "y")
        #expect(!document.savesToNewFile)
    }
}
