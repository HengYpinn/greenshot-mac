// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Self-Service › System: port of upstream `SystemInfoSectionViewModel.cs` (environment, memory, process, uptime) with
/// the screens and their scaling, and "Copy System Info".
@MainActor
final class SystemSectionModel: ObservableObject {
    @Published private(set) var snapshot: EnvironmentSnapshot
    private let live: Bool

    init() {
        snapshot = SystemInfo.snapshot()
        live = true
    }

    /// Fixed values (snapshots).
    init(sample: EnvironmentSnapshot) {
        snapshot = sample
        live = false
    }

    func refresh() {
        if live { snapshot = SystemInfo.snapshot() }
    }

    var report: String { DiagnosticReport.systemReport(snapshot) }

    func copyReport() {
        // Through Clipboard: the write is recorded as Greenshot's own (recipe Clipboard triggers ignore it).
        Clipboard.copy(text: report)
    }
}

struct SystemSectionView: View {
    @ObservedObject var model: SystemSectionModel
    var status: (String) -> Void

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 14) {
            SectionCard(title: String(localized: "Software")) {
                InfoRow(label: String(localized: "App", comment: "This application"),
                        value: String(localized: "\(s.appName) \(s.version) (build \(s.build))"))
                InfoRow(label: String(localized: "Runs as"), value: Self.architectureText(s.architecture, translated: s.translated))
                InfoRow(label: "macOS", value: s.osVersion)
                if !s.locale.isEmpty { InfoRow(label: String(localized: "Region", comment: "The region (locale) of the Mac"), value: s.locale) }
            }
            SectionCard(title: "Mac") {
                if !s.model.isEmpty { InfoRow(label: String(localized: "Model", comment: "The model of the Mac"), value: s.model) }
                if !s.chip.isEmpty { InfoRow(label: String(localized: "Chip", comment: "The processor of the Mac"), value: s.chip) }
                InfoRow(label: String(localized: "Memory"), value: DiagnosticReport.byteCount(s.physicalMemory))
                if !s.thermalState.isEmpty { InfoRow(label: String(localized: "Thermal state"), value: Self.thermalText(s.thermalState)) }
                InfoRow(label: String(localized: "Low Power Mode"),
                        value: s.lowPowerMode ? String(localized: "On", comment: "Low Power Mode is on") : String(localized: "Off", comment: "Low Power Mode is off"))
            }
            SectionCard(title: String(localized: "This app")) {
                if let memory = s.appMemory { InfoRow(label: String(localized: "Memory"), value: DiagnosticReport.byteCount(memory)) }
                if let peak = s.peakMemory { InfoRow(label: String(localized: "Most memory used"), value: DiagnosticReport.byteCount(peak)) }
                if let threads = s.threads { InfoRow(label: String(localized: "Threads"), value: "\(threads)") }
                if let launched = s.launched {
                    InfoRow(label: String(localized: "Running for"), value: DiagnosticReport.duration(s.now.timeIntervalSince(launched)))
                }
            }
            SectionCard(title: s.screens.count == 1 ? String(localized: "Screen") : String(localized: "Screens")) {
                ForEach(Array(s.screens.enumerated()), id: \.offset) { _, screen in
                    InfoRow(label: screen.name, value: Self.screenText(screen))
                }
            }
            SectionCard(title: String(localized: "Full report")) {
                ReportText(text: model.report, height: 150)
                HStack {
                    Spacer()
                    Button("Copy System Info") {
                        model.copyReport()
                        status(String(localized: "System information copied to the clipboard."))
                    }
                }
            }
        }
    }

    static func screenText(_ screen: EnvironmentSnapshot.Screen) -> String {
        let scale: String = String(format: "%g×", screen.scale)
        let pixelWidth: Int = Int(Double(screen.width) * screen.scale)
        let pixelHeight: Int = Int(Double(screen.height) * screen.scale)
        // Sizes as digits without grouping, like the report ("3024 × 1964").
        let points = "\(screen.width) × \(screen.height)"
        let pixels = "\(pixelWidth) × \(pixelHeight)"
        var parts = [String(localized: "\(points) points at \(scale) = \(pixels) pixels")]
        if screen.refreshRate > 0 { parts.append("\(screen.refreshRate) Hz") }
        if screen.edrPotential > 1 {
            let now = String(format: "%.1f", screen.edrNow)
            let potential = String(format: "%.1f", screen.edrPotential)
            parts.append(String(localized: "HDR, headroom \(now) of \(potential)"))
        } else {
            parts.append("SDR")
        }
        if !screen.colorSpace.isEmpty { parts.append(screen.colorSpace) }
        if screen.isMain { parts.append(String(localized: "with the menu bar", comment: "This screen shows the menu bar")) }
        return parts.joined(separator: ", ")
    }

    /// "arm64 app", "x86_64 app under Rosetta".
    static func architectureText(_ architecture: String, translated: Bool) -> String {
        translated ? String(localized: "\(architecture) app under Rosetta") : String(localized: "\(architecture) app")
    }

    /// The thermal state of `SystemInfo` (English in the report) as the window shows it.
    static func thermalText(_ state: String) -> String {
        switch state {
        case "nominal": return String(localized: "nominal", comment: "The thermal state of the Mac: normal")
        case "fair": return String(localized: "fair", comment: "The thermal state of the Mac: a bit warm")
        case "serious": return String(localized: "serious", comment: "The thermal state of the Mac: hot")
        case "critical": return String(localized: "critical", comment: "The thermal state of the Mac: too hot")
        default: return state
        }
    }
}
