// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Printer: port of the Printer tab of upstream `Greenshot/Settings/Views/SettingsWindow.xaml`.
struct PrinterSettings: View {
    @ObservedObject var store: SettingsStore

    private enum ColorMode: Hashable { case color, grayscale, monochrome }

    var body: some View {
        Form {
            Section {
                Toggle("Show print options every time before printing", isOn: store.binding(\.printing.promptOptions))
                    .managed(\.printing.promptOptions)
            }
            layoutSection
            colorSection
            footerSection
        }
        .formStyle(.grouped)
    }

    private var layoutSection: some View {
        Section("Layout") {
            Toggle("Shrink to fit the paper", isOn: store.binding(\.printing.allowShrink))
                .managed(\.printing.allowShrink)
            Toggle("Enlarge to fit the paper", isOn: store.binding(\.printing.allowEnlarge))
                .managed(\.printing.allowEnlarge)
            Toggle("Rotate to the page orientation", isOn: store.binding(\.printing.allowRotate))
                .managed(\.printing.allowRotate)
            Toggle("Center on the page", isOn: store.binding(\.printing.center))
                .managed(\.printing.center)
        }
    }

    private var colorSection: some View {
        Section("Colours") {
            Picker("Print in", selection: colorMode) {
                Text("Colour").tag(ColorMode.color)
                Text("Grayscale").tag(ColorMode.grayscale)
                Text("Black and white").tag(ColorMode.monochrome)
            }
            .pickerStyle(.radioGroup)
            .managed(\.printing.grayscale, \.printing.monochrome)
            if store.value.printing.monochrome {
                Slider(value: threshold, in: 0...255, step: 1) {
                    Text("Black and white threshold: \(store.value.printing.monochromeThreshold)")
                }
                .managed(\.printing.monochromeThreshold)
            }
            Toggle("Inverted colours", isOn: store.binding(\.printing.inverted))
                .managed(\.printing.inverted)
        }
    }

    private var footerSection: some View {
        Section {
            Toggle("Print a footer", isOn: store.binding(\.printing.footer))
                .managed(\.printing.footer)
            TextField("Footer pattern", text: store.binding(\.printing.footerPattern))
                .disabled(!store.value.printing.footer)
                .managed(\.printing.footerPattern)
            Text("Example: \(footerExample)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        } header: {
            Text("Footer")
        } footer: {
            Text("The same variables as the file name pattern, e.g. ${title} and ${capturetime:d\"D\"}.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footerExample: String {
        let context = store.patternContext(title: "Safari", date: Date(), consumeNumber: false)
        return FilenamePattern.fill(store.value.printing.footerPattern, context: context, filenameSafe: false)
    }

    private var colorMode: Binding<ColorMode> {
        Binding(
            get: {
                let p = store.value.printing
                return p.monochrome ? .monochrome : p.grayscale ? .grayscale : .color
            },
            set: { mode in
                store.update {
                    $0.printing.grayscale = mode == .grayscale
                    $0.printing.monochrome = mode == .monochrome
                }
            })
    }

    private var threshold: Binding<Double> {
        Binding(get: { Double(store.value.printing.monochromeThreshold) },
                set: { value in store.update { $0.printing.monochromeThreshold = Int(value.rounded()) } })
    }
}
