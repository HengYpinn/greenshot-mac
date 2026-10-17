// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

struct NotificationCapturesTests {
    private struct Counter: RandomNumberGenerator {
        var state: UInt64 = 0
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            return state
        }
    }

    @Test func idsAreVersion7UUIDs() {
        var generator = Counter()
        let date = Date(timeIntervalSince1970: 1_790_000_000.123)
        let id = NotificationCaptureStore.newId(now: date, using: &generator)
        #expect(UUID(uuidString: id) != nil)
        #expect(id == id.lowercased())
        let characters = Array(id)
        #expect(characters[14] == "7")
        #expect("89ab".contains(characters[19]))
        // The first 48 bits are the time in milliseconds.
        let prefix = id.replacingOccurrences(of: "-", with: "").prefix(12)
        let milliseconds = UInt64(prefix, radix: 16)
        #expect(milliseconds == 1_790_000_000_123)
    }

    @Test func idsSortByTime() {
        let earlier = NotificationCaptureStore.newId(now: Date(timeIntervalSince1970: 1_000))
        let later = NotificationCaptureStore.newId(now: Date(timeIntervalSince1970: 2_000))
        #expect(earlier < later)
        #expect(earlier != NotificationCaptureStore.newId(now: Date(timeIntervalSince1970: 1_000)))
    }

    @Test func onlyAnIdNamesAFile() {
        let store = NotificationCaptureStore(folder: URL(fileURLWithPath: "/tmp/store", isDirectory: true))
        let id = "0190A6E0-0000-7000-8000-00000000ABCD"
        #expect(store.captureURL(id)?.path == "/tmp/store/0190a6e0-0000-7000-8000-00000000abcd.png")
        #expect(store.attachmentURL(id)?.lastPathComponent == "0190a6e0-0000-7000-8000-00000000abcd-attachment.png")
        #expect(store.captureURL("../../etc/passwd") == nil)
        #expect(store.captureURL("") == nil)
        #expect(store.captureURL("0190a6e0-0000-7000-8000-00000000abcd/..") == nil)
        #expect(NotificationCaptureStore.canonicalId(nil) == nil)
    }

    @Test func filesLiveAnHour() {
        let now = Date(timeIntervalSince1970: 10_000)
        let files: [(name: String, modified: Date)] = [("old.png", now.addingTimeInterval(-3_601)),
                                                       ("young.png", now.addingTimeInterval(-3_599)),
                                                       ("future.png", now.addingTimeInterval(60))]
        #expect(NotificationCaptureStore.expiredFiles(files, now: now) == ["old.png"])
    }

    @Test func thumbnailFitsAndNeverGrows() {
        let wide = NotificationThumbnail.size(for: CGSize(width: 2880, height: 1800))
        #expect(wide == CGSize(width: 576, height: 360))
        let long = NotificationThumbnail.size(for: CGSize(width: 4000, height: 200))
        #expect(long == CGSize(width: 728, height: 36))
        let small = NotificationThumbnail.size(for: CGSize(width: 100, height: 50))
        #expect(small == CGSize(width: 100, height: 50))
        let line = NotificationThumbnail.size(for: CGSize(width: 10_000, height: 1))
        #expect(line == CGSize(width: 728, height: 1))
        #expect(NotificationThumbnail.size(for: .zero) == CGSize(width: 1, height: 1))
    }

    @Test func thumbnailImageHasThatSize() throws {
        let image = TestImage.solid(width: 1456, height: 720, .red)
        let thumbnail = try #require(NotificationThumbnail.make(image))
        #expect(thumbnail.width == 728)
        #expect(thumbnail.height == 360)
        #expect(TestImage.pixel(thumbnail, 10, 10).isClose(to: .red))
    }
}
