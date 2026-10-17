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
            SectionCard(title: "Software") {
                InfoRow(label: "App", value: "\(s.appName) \(s.version) (build \(s.build))")
                InfoRow(label: "Runs as", value: s.architecture + (s.translated ? " app under Rosetta" : " app"))
                InfoRow(label: "macOS", value: s.osVersion)
                if !s.locale.isEmpty { InfoRow(label: "Region", value: s.locale) }
            }
            SectionCard(title: "Mac") {
                if !s.model.isEmpty { InfoRow(label: "Model", value: s.model) }
                if !s.chip.isEmpty { InfoRow(label: "Chip", value: s.chip) }
                InfoRow(label: "Memory", value: DiagnosticReport.byteCount(s.physicalMemory))
                if !s.thermalState.isEmpty { InfoRow(label: "Thermal state", value: s.thermalState) }
                InfoRow(label: "Low Power Mode", value: s.lowPowerMode ? "On" : "Off")
            }
            SectionCard(title: "This app") {
                if let memory = s.appMemory { InfoRow(label: "Memory", value: DiagnosticReport.byteCount(memory)) }
                if let peak = s.peakMemory { InfoRow(label: "Most memory used", value: DiagnosticReport.byteCount(peak)) }
                if let threads = s.threads { InfoRow(label: "Threads", value: "\(threads)") }
                if let launched = s.launched {
                    InfoRow(label: "Running for", value: DiagnosticReport.duration(s.now.timeIntervalSince(launched)))
                }
            }
            SectionCard(title: s.screens.count == 1 ? "Screen" : "Screens") {
                ForEach(Array(s.screens.enumerated()), id: \.offset) { _, screen in
                    InfoRow(label: screen.name, value: Self.screenText(screen))
                }
            }
            SectionCard(title: "Full report") {
                ReportText(text: model.report, height: 150)
                HStack {
                    Spacer()
                    Button("Copy System Info") {
                        model.copyReport()
                        status("System information copied to the clipboard.")
                    }
                }
            }
        }
    }

    static func screenText(_ screen: EnvironmentSnapshot.Screen) -> String {
        let scale: String = String(format: "%g×", screen.scale)
        let pixelWidth: Int = Int(Double(screen.width) * screen.scale)
        let pixelHeight: Int = Int(Double(screen.height) * screen.scale)
        var parts = ["\(screen.width) × \(screen.height) points at \(scale) = \(pixelWidth) × \(pixelHeight) pixels"]
        if screen.refreshRate > 0 { parts.append("\(screen.refreshRate) Hz") }
        parts.append(screen.edrPotential > 1 ? String(format: "HDR, headroom %.1f of %.1f", screen.edrNow, screen.edrPotential) : "SDR")
        if !screen.colorSpace.isEmpty { parts.append(screen.colorSpace) }
        if screen.isMain { parts.append("with the menu bar") }
        return parts.joined(separator: ", ")
    }
}
