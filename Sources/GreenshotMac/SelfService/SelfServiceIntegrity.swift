// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Self-Service › Integrity: the code signature instead of upstream's `checksum.SHA256` (`ChecksumSectionViewModel.cs`):
/// whether a file of the app was changed or damaged, who signed it, whether Apple notarized it, and whether macOS runs a
/// quarantined or translocated copy (an app started from a download folder may not keep its permissions).
@MainActor
final class IntegritySectionModel: ObservableObject {
    @Published private(set) var report: SignatureReport?
    private let live: Bool
    private var checking = false

    init() {
        live = true
    }

    /// Fixed values (snapshots).
    init(sample: SignatureReport) {
        live = false
        report = sample
    }

    var problemCount: Int { report?.problemCount ?? 0 }

    func refresh() {
        guard live, !checking else { return }
        checking = true
        Task.detached(priority: .utility) {
            var result = CodeSignature.check()
            let needsNotarization = result.notarization == .checking
            await MainActor.run { [result] in
                self.report = result
            }
            if needsNotarization {
                result.notarization = CodeSignature.isNotarized() ? .notarized : .notNotarized
            }
            await MainActor.run { [result] in
                self.report = result
                self.checking = false
            }
        }
    }

    func copyReport() {
        guard let report else { return }
        // Through Clipboard: the write is recorded as Greenshot's own (recipe Clipboard triggers ignore it).
        Clipboard.copy(text: report.reportText)
    }
}

struct IntegritySectionView: View {
    @ObservedObject var model: IntegritySectionModel
    var status: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let report = model.report {
                SectionCard(title: String(localized: "Code signature")) {
                    HStack(spacing: 8) {
                        signatureIcon(report.valid)
                        Text(report.shownValidity ?? report.validity).fixedSize(horizontal: false, vertical: true)
                    }
                    InfoRow(label: String(localized: "Signed by"), value: report.shownSigner ?? report.signer)
                    if let identifier = report.identifier { InfoRow(label: String(localized: "Identifier", comment: "The bundle identifier of the app"), value: identifier) }
                    if let team = report.teamID { InfoRow(label: String(localized: "Team", comment: "The developer team ID of the signature"), value: team) }
                    InfoRow(label: String(localized: "Hardened runtime"), value: report.hardenedRuntime ? String(localized: "Yes") : String(localized: "No"))
                    if let hash = report.cdHash { InfoRow(label: String(localized: "Code hash"), value: hash) }
                    InfoRow(label: String(localized: "Notarized"), value: report.shownNotarization)
                }
                SectionCard(title: String(localized: "Where it runs from")) {
                    InfoRow(label: String(localized: "Location", comment: "Where the app is on the disk"), value: report.location)
                    InfoRow(label: String(localized: "Quarantined"),
                            value: report.quarantined ? String(localized: "Yes: downloaded and not opened from Finder yet") : String(localized: "No"))
                    if report.translocated {
                        Label("macOS runs a temporary copy (App Translocation). Move the app to the Applications folder and open it from there, so its permissions and login item stay.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    } else {
                        InfoRow(label: String(localized: "Translocated"), value: String(localized: "No"))
                    }
                }
                SectionCard(title: String(localized: "Report", comment: "Title of the integrity report (a noun)")) {
                    ReportText(text: report.reportText, height: 140)
                    HStack {
                        Spacer()
                        Button("Copy Report") {
                            model.copyReport()
                            status(String(localized: "Copied the integrity report."))
                        }
                    }
                }
            } else {
                ProgressView("Checking the code signature…")
            }
        }
    }

    @ViewBuilder private func signatureIcon(_ valid: Bool?) -> some View {
        switch valid {
        case true?: Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case false?: Image(systemName: "xmark.seal.fill").foregroundStyle(.red)
        case nil: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}
