// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Capture (upstream's Capture tab, `Greenshot/Settings/Views/SettingsWindow.xaml`).
struct CaptureSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Capturing") {
                Toggle("Capture the mouse pointer", isOn: store.binding(\.captureMousePointer))
                    .help("M on the capture screen switches it for one capture.")
                Toggle("Use interactive window capture mode", isOn: store.binding(\.interactiveWindowCapture))
                    .help("The window hotkey opens the capture screen in window mode instead of capturing the active window.")
                Toggle("Keep the window shadow in window captures", isOn: store.binding(\.includeWindowShadow))
                Toggle("Show the zoomer on the capture screen", isOn: store.binding(\.zoomerEnabled))
                Toggle("Look for QR codes on the capture screen", isOn: store.binding(\.scanQRCodesOnCapture))
                Toggle("Play the camera sound", isOn: store.binding(\.playCameraSound))
                Stepper(value: store.binding(\.captureDelayMilliseconds), in: 0...10_000, step: 100) {
                    Text("Wait before capturing: \(store.value.captureDelayMilliseconds) ms")
                }
            }
            FullScreenSettings(store: store)
            FixedSizeSettings(store: store)
            TextRecognitionSettings(store: store)
            NotificationSettings(store: store)
        }
        .formStyle(.grouped)
    }
}

/// What the full screen hotkey captures (upstream `ScreenCaptureMode`, `ScreenToCapture`).
private struct FullScreenSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section("Full screen hotkey") {
            Picker("Captures", selection: store.binding(\.screenCaptureMode)) {
                ForEach(ScreenCaptureMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if store.value.screenCaptureMode == .fixed {
                Stepper(value: store.binding(\.screenToCapture), in: 1...9) {
                    Text("Screen \(store.value.screenToCapture)\(screenName)")
                }
            }
        }
    }

    private var screenName: String {
        let screens = NSScreen.screens
        let index = store.value.screenToCapture - 1
        return screens.indices.contains(index) ? ": \(screens[index].localizedName)" : " (not connected)"
    }
}

/// The text typed for a new fixed size.
private final class CaptureSizeDraft: ObservableObject {
    @Published var text = ""
}

/// Upstream "Fixed capture sizes": the sizes of the fixed-size mode, in the order 1–9 pick them.
private struct FixedSizeSettings: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var draft = CaptureSizeDraft()

    var body: some View {
        Section {
            ForEach(Array(store.value.fixedCaptureSizes.enumerated()), id: \.offset) { index, size in
                HStack {
                    Text(index < 9 ? "\(index + 1)" : "").monospacedDigit().foregroundStyle(.secondary).frame(width: 16)
                    Text(verbatim: "\(size.width) × \(size.height) pixels").monospacedDigit()
                    Spacer()
                    Button("Remove") { remove(at: index) }
                }
            }
            HStack {
                TextField("Size", text: $draft.text, prompt: Text("1280x720"))
                    .onSubmit(add)
                Button("Add", action: add).disabled(newSizes.isEmpty)
            }
        } header: {
            Text("Fixed capture sizes")
        } footer: {
            Text("F on the capture screen captures an area of one of these sizes; the last five region sizes follow them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var newSizes: [CaptureSize] { FixedSizeCapture.parseSizes(draft.text) }

    private func add() {
        let sizes = newSizes
        guard !sizes.isEmpty else {
            NSSound.beep()
            return
        }
        store.update { values in
            for size in sizes where !values.fixedCaptureSizes.contains(size) { values.fixedCaptureSizes.append(size) }
        }
        draft.text = ""
    }

    private func remove(at index: Int) {
        store.update { values in
            guard values.fixedCaptureSizes.indices.contains(index) else { return }
            values.fixedCaptureSizes.remove(at: index)
        }
    }
}

/// Upstream "Text recognition (OCR)": the language of the text mode and the OCR destination.
private struct TextRecognitionSettings: View {
    @ObservedObject var store: SettingsStore
    private static let languages = TextRecognizer.supportedLanguages()

    var body: some View {
        Section("Text recognition (OCR)") {
            Picker("Language of the text", selection: store.binding(\.ocrLanguage)) {
                Text("Automatic").tag("")
                ForEach(Self.languages, id: \.self) { Text(Self.name(of: $0)).tag($0) }
                if !store.value.ocrLanguage.isEmpty && !Self.languages.contains(store.value.ocrLanguage) {
                    Text(store.value.ocrLanguage).tag(store.value.ocrLanguage)
                }
            }
        }
    }

    private static func name(of code: String) -> String {
        Locale.current.localizedString(forIdentifier: code).map { "\($0) (\(code))" } ?? code
    }
}

/// Upstream `NotificationLevel`. "None" also turns off "Show a message after saving or copying".
private struct NotificationSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section("Messages") {
            Picker("Show messages", selection: level) {
                ForEach(NotificationLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var level: Binding<NotificationLevel> {
        Binding(get: { store.value.showNotifications ? store.value.notificationLevel : .none },
                set: { newValue in
                    store.update { values in
                        values.notificationLevel = newValue
                        values.showNotifications = newValue != .none
                    }
                })
    }
}
