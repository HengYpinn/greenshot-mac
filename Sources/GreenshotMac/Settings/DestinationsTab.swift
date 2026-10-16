// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Destinations: upstream's Destination tab (where a capture goes) with the settings of the
/// destinations that have some (mail, PDF, external commands).
struct DestinationsSettings: View {
    @ObservedObject var store: SettingsStore
    static let choices: [CaptureDestination] = CaptureDestination.allCases.filter { $0 != .picker }

    var body: some View {
        Form {
            afterCaptureSection
            emailSection
        }
        .formStyle(.grouped)
    }

    private var afterCaptureSection: some View {
        Section {
            Toggle("Ask every time (destination menu)", isOn: destination(.picker))
            // Never disabled: with the menu on and nothing else chosen, there would be no way to switch.
            ForEach(Self.choices, id: \.self) { candidate in
                Toggle(candidate.displayName, isOn: destination(candidate))
            }
        } header: {
            Text("After a capture")
        } footer: {
            Text("Turning on any of the others turns off the menu. Several can be on, e.g. copy and save.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var emailSection: some View {
        Section {
            TextField("To", text: store.binding(\.email.to))
            TextField("CC", text: store.binding(\.email.cc))
            TextField("BCC", text: store.binding(\.email.bcc))
            TextField("Subject", text: store.binding(\.email.subjectPattern))
        } header: {
            Text("Email")
        } footer: {
            Text("Separate addresses with commas. The subject can use the file name pattern variables, e.g. ${title}. The macOS mail service fills in To and the subject; CC and BCC are shown to add by hand.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// "Ask every time" excludes the others, like upstream's picker; without any destination it comes back.
    private func destination(_ candidate: CaptureDestination) -> Binding<Bool> {
        Binding(
            get: { store.value.destinations.contains(candidate) },
            set: { on in store.update { $0.setDestination(candidate, on: on) } })
    }
}
