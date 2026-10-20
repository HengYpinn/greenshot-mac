// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import GreenshotCore

private func at(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

/// The seconds of an output time, nil when the sample is left out.
private func seconds(_ time: CMTime?) -> Double? { time?.seconds }

struct RecordingTimelineTests {
    @Test func startsAtTheFirstFrame() {
        var timeline = RecordingTimeline()
        #expect(timeline.outputTime(for: at(100)) == nil)
        timeline.begin(at: at(100))
        let first = seconds(timeline.outputTime(for: at(100)))
        #expect(first == 0)
        let later = seconds(timeline.outputTime(for: at(101.5)))
        #expect(later == 1.5)
        #expect(timeline.outputTime(for: at(99)) == nil)
    }

    @Test func pausesAreLeftOut() {
        var timeline = RecordingTimeline()
        timeline.begin(at: at(100))
        timeline.pause(at: at(102))
        #expect(timeline.outputTime(for: at(103)) == nil)
        let during = timeline.duration(at: at(104)).seconds
        #expect(during == 2)
        timeline.resume(at: at(105))
        #expect(timeline.outputTime(for: at(104)) == nil)
        let after = seconds(timeline.outputTime(for: at(106)))
        #expect(after == 3)
        let total = timeline.duration(at: at(107)).seconds
        #expect(total == 4)
    }

    @Test func twoPausesAddUp() {
        var timeline = RecordingTimeline()
        timeline.begin(at: at(0))
        timeline.pause(at: at(1))
        timeline.resume(at: at(3))
        timeline.pause(at: at(4))
        timeline.resume(at: at(10))
        let output = seconds(timeline.outputTime(for: at(11)))
        #expect(output == 3)
        #expect(!timeline.isPaused)
    }

    /// Where sound that starts before the first frame or in a pause gets into the video.
    @Test func recordedTimeSkipsWhatIsLeftOut() {
        var timeline = RecordingTimeline()
        #expect(timeline.recordedTime(from: at(99)) == nil)
        timeline.begin(at: at(100))
        #expect(seconds(timeline.recordedTime(from: at(99.5))) == 100)
        #expect(seconds(timeline.recordedTime(from: at(101))) == 101)
        timeline.pause(at: at(102))
        timeline.resume(at: at(105))
        #expect(seconds(timeline.recordedTime(from: at(103))) == 105)
        #expect(seconds(timeline.recordedTime(from: at(106))) == 106)
        timeline.pause(at: at(107))
        #expect(timeline.recordedTime(from: at(108)) == nil)
        #expect(seconds(timeline.recordedTime(from: at(106.5))) == 106.5)
    }

    /// A resume and a pause at the same time: the time after both.
    @Test func recordedTimeAfterTwoPausesInARow() {
        var timeline = RecordingTimeline()
        timeline.begin(at: at(0))
        timeline.pause(at: at(1))
        timeline.resume(at: at(2))
        timeline.pause(at: at(2))
        timeline.resume(at: at(3))
        #expect(seconds(timeline.recordedTime(from: at(1.5))) == 3)
        let output = seconds(timeline.outputTime(for: at(3)))
        #expect(output == 1)
    }

    @Test func aPauseBeforeTheFirstFrameChangesNothing() {
        var timeline = RecordingTimeline()
        timeline.pause(at: at(1))
        timeline.resume(at: at(2))
        timeline.begin(at: at(5))
        let output = seconds(timeline.outputTime(for: at(6)))
        #expect(output == 1)
    }
}

struct RecordingGeometryTests {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let left = CGRect(x: -1920, y: -180, width: 1920, height: 1080)

    @Test func regionOnOneDisplay() throws {
        let part = try #require(RecordingGeometry.displayRegion(for: CGRect(x: 100, y: 50, width: 400, height: 300), displays: [main, left]))
        #expect(part.displayIndex == 0)
        #expect(part.sourceRect == CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    @Test func regionOverTwoDisplaysTakesTheLargerPart() throws {
        let region = CGRect(x: -600, y: 100, width: 800, height: 200)
        let part = try #require(RecordingGeometry.displayRegion(for: region, displays: [main, left]))
        #expect(part.displayIndex == 1)
        #expect(part.globalRect == CGRect(x: -600, y: 100, width: 600, height: 200))
        #expect(part.sourceRect == CGRect(x: 1320, y: 280, width: 600, height: 200))
    }

    @Test func regionOffEveryDisplay() {
        #expect(RecordingGeometry.displayRegion(for: CGRect(x: 5000, y: 0, width: 100, height: 100), displays: [main]) == nil)
    }

    @Test func letterboxKeepsTheSizeAndCentres() {
        let canvas = CGSize(width: 1000, height: 800)
        let smaller = RecordingGeometry.placement(content: CGSize(width: 600, height: 400), canvas: canvas, behavior: .letterboxFixedCanvas)
        #expect(smaller == CGRect(x: 200, y: 200, width: 600, height: 400))
        let wider = RecordingGeometry.placement(content: CGSize(width: 2000, height: 800), canvas: canvas, behavior: .letterboxFixedCanvas)
        #expect(wider == CGRect(x: 0, y: 200, width: 1000, height: 400))
    }

    @Test func scaleToFitFills() {
        let canvas = CGSize(width: 1000, height: 800)
        let smaller = RecordingGeometry.placement(content: CGSize(width: 500, height: 200), canvas: canvas, behavior: .scaleToFit)
        #expect(smaller == CGRect(x: 0, y: 200, width: 1000, height: 400))
        let same = RecordingGeometry.placement(content: canvas, canvas: canvas, behavior: .scaleToFit)
        #expect(same == CGRect(origin: .zero, size: canvas))
    }

    @Test func streamSizeIsEven() {
        let size = RecordingGeometry.streamSize(points: CGSize(width: 801, height: 451), scale: 2, factor: 0.5)
        #expect(size.width == 800)
        #expect(size.height == 450)
    }
}

struct RecordingOutputPathTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    /// 2026-10-17 14:30:05 UTC.
    private let date = Date(timeIntervalSince1970: 1_792_247_405)
    private let utc = TimeZone(identifier: "UTC")!

    private func context(title: String = "Safari") -> FilenamePattern.Context {
        FilenamePattern.Context(captureTime: date, title: title, homeDirectory: home, timeZone: utc)
    }

    @Test func settingsFolderAndPattern() {
        let url = RecordingOutputPath.url(folder: "~/Movies/Greenshot", pattern: VideoSettings().filenamePattern,
                                          context: context(), exists: { _ in false })
        defer { RecordingOutputPath.release(url) }
        #expect(url.path == "/Users/tester/Movies/Greenshot/Greenshot_Recording_20261017_143005.mp4")
        let titled = RecordingOutputPath.url(folder: "", pattern: "${title}", context: context(), exists: { _ in false })
        defer { RecordingOutputPath.release(titled) }
        #expect(titled.path == "/Users/tester/Movies/Greenshot/Safari.mp4")
    }

    @Test func anExistingFileIsKept() {
        let taken = "/Users/tester/Movies/Greenshot/Mail.mp4"
        let url = RecordingOutputPath.url(folder: "~/Movies/Greenshot", pattern: "${title}", context: context(title: "Mail"),
                                          exists: { $0.path == taken })
        defer { RecordingOutputPath.release(url) }
        #expect(url.path == "/Users/tester/Movies/Greenshot/Mail (2).mp4")
    }

    /// Two recordings asked for in the same second don't get the same file: the first one's path is reserved until
    /// its recording ended.
    @Test func aPathIsReservedUntilReleased() {
        let first = RecordingOutputPath.url(folder: "~/Clips", pattern: "${title}", context: context(title: "Notes"),
                                            exists: { _ in false })
        let second = RecordingOutputPath.url(folder: "~/Clips", pattern: "${title}", context: context(title: "Notes"),
                                             exists: { _ in false })
        #expect(first.path == "/Users/tester/Clips/Notes.mp4")
        #expect(second.path == "/Users/tester/Clips/Notes (2).mp4")
        RecordingOutputPath.release(first)
        let third = RecordingOutputPath.url(folder: "~/Clips", pattern: "${title}", context: context(title: "Notes"),
                                            exists: { _ in false })
        #expect(third.path == "/Users/tester/Clips/Notes.mp4")
        RecordingOutputPath.release(second)
        RecordingOutputPath.release(third)
    }

    @Test func recipePaths() {
        let environment = ["HOME": "/Users/tester", "PROJECT": "demo"]
        let file = RecordingOutputPath.recipeURL(outputFilePath: "%home%/Videos/%PROJECT%_{yyyyMMdd_HHmmss}.mp4",
                                                 outputDirectory: nil, filenamePattern: nil, date: date,
                                                 environment: environment, homeDirectory: home, timeZone: utc)
        #expect(file.path == "/Users/tester/Videos/demo_20261017_143005.mp4")
        let directory = RecordingOutputPath.recipeURL(outputFilePath: nil, outputDirectory: "~/Clips", filenamePattern: nil,
                                                      date: date, environment: environment, homeDirectory: home, timeZone: utc)
        #expect(directory.path == "/Users/tester/Clips/Greenshot_20261017_143005.mp4")
        let fallback = RecordingOutputPath.recipeURL(outputFilePath: " ", outputDirectory: nil, filenamePattern: nil,
                                                     date: date, environment: environment, homeDirectory: home, timeZone: utc)
        #expect(fallback.path == "/Users/tester/Movies/Greenshot/Greenshot_Recording_20261017_143005.mp4")
    }

    @Test func environmentVariablesLikeDotNet() {
        let environment = ["USER": "tester"]
        #expect(RecordingOutputPath.expandEnvironmentVariables("%user%-%NOPE%-100%", environment: environment) == "tester-%NOPE%-100%")
        #expect(RecordingOutputPath.expandEnvironmentVariables("50%%USER%", environment: environment) == "50%tester")
    }
}

struct RecordingWindowMatcherTests {
    private struct Window: Equatable {
        var title: String
        var app: String
        var bundle: String
    }

    private let windows = [Window(title: "Inbox – Mail", app: "Mail", bundle: "com.apple.mail"),
                           Window(title: "Quarterly report.pdf", app: "Preview", bundle: "com.apple.Preview"),
                           Window(title: "Greenshot – GitHub", app: "Safari", bundle: "com.apple.Safari")]

    private func first(_ query: WindowMatchQuery, active: Window? = nil) -> Window? {
        query.firstMatch(in: windows, active: active, title: { $0.title }, names: { [$0.app, $0.bundle] })
    }

    @Test func titleContainsAnyCase() {
        #expect(first(WindowMatchQuery(title: "report"))?.app == "Preview")
        #expect(first(WindowMatchQuery(title: "REPORT"))?.app == "Preview")
        #expect(first(WindowMatchQuery(title: "REPORT", matchCase: true)) == nil)
    }

    @Test func patternWinsAndABadOneIsLeftOut() {
        #expect(first(WindowMatchQuery(title: "Inbox", titlePattern: "^greenshot"))?.app == "Safari")
        // An invalid pattern is ignored: the title is used.
        #expect(first(WindowMatchQuery(title: "Inbox", titlePattern: "(["))?.app == "Mail")
    }

    @Test func processByNameOrBundle() {
        #expect(first(WindowMatchQuery(processName: "Safari.app"))?.app == "Safari")
        #expect(first(WindowMatchQuery(processName: "com.apple.Preview"))?.app == "Preview")
        #expect(first(WindowMatchQuery(title: "report", processName: "Mail")) == nil)
    }

    @Test func theActiveWindowFirst() {
        let active = windows[2]
        #expect(first(WindowMatchQuery(title: "–"), active: active)?.app == "Safari")
        #expect(first(WindowMatchQuery(title: "–"))?.app == "Mail")
        #expect(WindowMatchQuery().isEmpty)
    }
}

struct RecordingAudioMixerTests {
    private func constant(_ value: Float, frames: Int) -> [Float] { [Float](repeating: value, count: frames * 2) }

    @Test func alignedSourcesAreAdded() throws {
        var mixer = RecordingAudioMixer(sampleRate: 1000)
        mixer.add(constant(0.25, frames: 100), source: 0, at: 10)
        #expect(mixer.mix() == nil)
        mixer.add(constant(0.5, frames: 100), source: 1, at: 10)
        let mix = mixer.mix()
        let mixed = try #require(mix)
        #expect(mixed.samples.count == 200)
        #expect(mixed.time == 10)
        let first = mixed.samples[0]
        #expect(first == 0.75)
    }

    @Test func loudPartsAreClipped() throws {
        var mixer = RecordingAudioMixer(sampleRate: 1000)
        mixer.add(constant(0.8, frames: 10), source: 0, at: 0)
        mixer.add(constant(0.8, frames: 10), source: 1, at: 0)
        let mix = mixer.mix()
        let mixed = try #require(mix)
        let first = mixed.samples[0]
        #expect(first == 1)
    }

    @Test func aLaterSourceIsPlacedByItsTime() throws {
        var mixer = RecordingAudioMixer(sampleRate: 1000)
        mixer.add(constant(0.25, frames: 200), source: 0, at: 0)
        mixer.add(constant(0.5, frames: 100), source: 1, at: 0.1)
        let mix = mixer.mix()
        let mixed = try #require(mix)
        #expect(mixed.samples.count == 400)
        let before = mixed.samples[2 * 50]
        let after = mixed.samples[2 * 150]
        #expect(before == 0.25)
        #expect(after == 0.75)
    }

    @Test func aSilentSourceIsSilenceAfterTheLag() throws {
        var mixer = RecordingAudioMixer(sampleRate: 1000)
        mixer.add(constant(0.25, frames: 1000), source: 0, at: 0)
        let mix = mixer.mix()
        let mixed = try #require(mix)
        // One second from one source, half a second of lag allowed.
        #expect(mixed.samples.count == 1000)
        let flushed = mixer.mix(flush: true)
        let rest = try #require(flushed)
        #expect(rest.time == 0.5)
        #expect(rest.samples.count == 1000)
    }
}
