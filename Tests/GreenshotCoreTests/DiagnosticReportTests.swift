// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import GreenshotCore

struct DiagnosticReportTests {
    static var snapshot: EnvironmentSnapshot {
        var snapshot = EnvironmentSnapshot(appName: "Greenshot for Mac (Community)", version: "1.4.0", build: "140",
                                           architecture: "Apple silicon", osVersion: "Version 27.0 (Build 27A100)",
                                           now: Date(timeIntervalSince1970: 1_790_000_000))
        snapshot.timeZone = TimeZone(secondsFromGMT: 8 * 3_600) ?? .current
        snapshot.model = "Mac15,3"
        snapshot.chip = "Apple M3"
        snapshot.physicalMemory = 16 << 30
        snapshot.appMemory = 84 << 20
        snapshot.peakMemory = 120 << 20
        snapshot.threads = 9
        snapshot.launched = Date(timeIntervalSince1970: 1_790_000_000 - 93_784)
        snapshot.locale = "en_SG"
        snapshot.thermalState = "nominal"
        snapshot.screens = [
            .init(name: "Built-in Retina Display", width: 1512, height: 982, scale: 2, refreshRate: 120, edrNow: 1, edrPotential: 16,
                  colorSpace: "Color LCD", isMain: true),
            .init(name: "DELL U2720Q", width: 2560, height: 1440, scale: 1, refreshRate: 60),
        ]
        return snapshot
    }

    @Test func environmentLines() {
        let text = DiagnosticReport.environmentText(Self.snapshot, newline: true)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines[0] == "Software version: Greenshot for Mac (Community) 1.4.0 (build 140, Apple silicon)")
        #expect(lines[1] == "Time: 2026-09-21 22:13:20 +0800")
        #expect(lines[2] == "OS: macOS Version 27.0 (Build 27A100)")
        #expect(lines[3] == "Hardware: Mac15,3, Apple M3, 16.0 GB memory")
        #expect(lines[4] == "Screens: Built-in Retina Display 1512x982 pt @2x, 120 Hz, HDR (EDR 1.0 of 16.0), Color LCD, main; DELL U2720Q 2560x1440 pt @1x, 60 Hz")
        #expect(lines[5] == "Locale: en_SG")
        #expect(!DiagnosticReport.environmentText(Self.snapshot, newline: false).contains("\n"))
    }

    @Test func processLines() {
        let lines = DiagnosticReport.processText(Self.snapshot)
        #expect(lines.contains("App memory: 84.0 MB (peak 120.0 MB)"))
        #expect(lines.contains("Threads: 9"))
        #expect(lines.contains("Running for: 1d 02h 03m 04s"))
        #expect(lines.contains("Low Power Mode: off"))
    }

    @Test func translatedAppsSaySo() {
        var snapshot = Self.snapshot
        snapshot.architecture = "Intel"
        snapshot.translated = true
        #expect(DiagnosticReport.environmentText(snapshot, newline: true).hasPrefix(
            "Software version: Greenshot for Mac (Community) 1.4.0 (build 140, Intel under Rosetta)"))
    }

    @Test func settingsDumpListsOnlyChangesWithoutPersonalValues() {
        var settings = AppSettings()
        #expect(DiagnosticReport.settingsDump(settings).isEmpty)
        settings.outputFormat = .jpg
        settings.jpegQuality = 55
        settings.playCameraSound = true
        settings.outputFolder = "/Users/alex/Screenshots"
        settings.email.to = "alex@example.com"
        settings.jira.url = "https://example.atlassian.net"
        settings.jira.email = "alex@example.com"
        settings.jira.recentIssueKeys = ["SHOT-12"]
        settings.ocrLanguage = "en-US"
        let dump = DiagnosticReport.settingsDump(settings)
        #expect(dump.contains("outputFormat = \"jpg\""))
        #expect(dump.contains("jpegQuality = 55"))
        #expect(dump.contains("playCameraSound = true"))
        #expect(dump.contains("outputFolder = <set>"))
        #expect(dump.contains("email.to = <set>"))
        #expect(dump.contains("jira.url = <set>"))
        #expect(dump.contains("jira.email = <set>"))
        #expect(dump.contains("jira.recentIssueKeys[0] = <set>"))
        #expect(dump.contains("ocrLanguage = \"en-US\""))
        let joined = dump.joined(separator: "\n")
        #expect(!joined.contains("alex"))
        #expect(!joined.contains("atlassian"))
        #expect(!joined.contains("SHOT"))
    }

    @Test func freeTextOnlyShowsItsLength() {
        var settings = AppSettings()
        settings.filenamePattern = "${YYYY}-${title} by Alex"
        let dump = DiagnosticReport.settingsDump(settings)
        #expect(dump.contains("filenamePattern = <set>") || dump.contains("filenamePattern = <text, 24 characters>"))
        #expect(!dump.joined().contains("Alex"))
    }

    @Test func bugReportHasEnvironmentErrorAndSettings() {
        var settings = AppSettings()
        settings.theme = .dark
        let crash = CrashDetails(kind: .caughtException, type: "NSRangeException", message: "index 3 beyond bounds",
                                 frames: [CrashFrame(image: "GreenshotMac", symbol: "Editor.undo()")])
        let report = DiagnosticReport.bugReport(environment: Self.snapshot, crash: crash, settings: settings)
        #expect(report.hasPrefix("Software version: Greenshot for Mac (Community) 1.4.0"))
        #expect(report.contains("\nException: NSRangeException\nMessage: index 3 beyond bounds\n"))
        #expect(report.contains("Configuration dump (settings that differ from the defaults):\ntheme = \"dark\""))
    }

    @Test func formatting() {
        #expect(DiagnosticReport.byteCount(512) == "512 B")
        #expect(DiagnosticReport.byteCount(1_536) == "1.5 KB")
        #expect(DiagnosticReport.byteCount(3 << 30) == "3.0 GB")
        #expect(DiagnosticReport.duration(59) == "0d 00h 00m 59s")
        #expect(DiagnosticReport.abbreviatingHome("/Users/alex/Library/Logs", home: "/Users/alex") == "~/Library/Logs")
        #expect(DiagnosticReport.isWord("showMenu"))
        #expect(!DiagnosticReport.isWord("alex@example.com"))
        #expect(!DiagnosticReport.isWord("/Users/alex"))
        #expect(!DiagnosticReport.isWord("1abc"))
    }
}
