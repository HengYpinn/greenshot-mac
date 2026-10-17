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
                    .managed(\.captureMousePointer)
                Toggle("Use interactive window capture mode", isOn: store.binding(\.interactiveWindowCapture))
                    .help("The window hotkey opens the capture screen in window mode instead of capturing the active window.")
                    .managed(\.interactiveWindowCapture)
                Toggle("Keep the window shadow in window captures", isOn: store.binding(\.includeWindowShadow))
                    .managed(\.includeWindowShadow)
                WindowAreasSetting(store: store)
                HDRSetting(store: store)
                Toggle("Show the zoomer on the capture screen", isOn: store.binding(\.zoomerEnabled))
                    .managed(\.zoomerEnabled)
                ZoomerOpacitySetting(store: store)
                Toggle("Look for QR codes on the capture screen", isOn: store.binding(\.scanQRCodesOnCapture))
                    .managed(\.scanQRCodesOnCapture)
                Toggle("Play the camera sound", isOn: store.binding(\.playCameraSound))
                    .managed(\.playCameraSound)
                CameraSoundSetting(store: store)
                Stepper(value: store.binding(\.captureDelayMilliseconds), in: 0...10_000, step: 100) {
                    Text("Wait before capturing: \(store.value.captureDelayMilliseconds) ms")
                }
                .managed(\.captureDelayMilliseconds)
            }
            FullScreenSettings(store: store)
            FixedSizeSettings(store: store)
            TextRecognitionSettings(store: store)
            NotificationSettings(store: store)
        }
        .formStyle(.grouped)
    }
}

/// "Select areas inside windows" (upstream: window mode for beta testers, `WindowCaptureTool.SelectsAreas`). Turning it
/// on asks macOS for the Accessibility permission; without it window mode selects whole windows, as with the setting off.
struct WindowAreasSetting: View {
    @ObservedObject var store: SettingsStore
    @StateObject private var accessibility: AccessibilityStatus

    /// `accessibility` is given by the snapshots, to show the row without the permission.
    @MainActor
    init(store: SettingsStore, accessibility: AccessibilityStatus? = nil) {
        self.store = store
        _accessibility = StateObject(wrappedValue: accessibility ?? AccessibilityStatus())
    }

    var body: some View {
        Toggle("Select areas inside windows", isOn: enabled)
            .help("In window mode the selection follows the smallest area under the mouse, like a sidebar, a toolbar or a "
                  + "part of a web page; PgUp and PgDn select a larger or smaller area. Needs the Accessibility permission.")
            .managed(\.windowCaptureSelectsAreas)
        if store.value.windowCaptureSelectsAreas && !accessibility.isAllowed {
            LabeledContent {
                HStack {
                    Button("Allow…") {
                        Permissions.requestAccessibility()
                        accessibility.refresh()
                    }
                    Button("Open System Settings") { NSWorkspace.shared.open(Permissions.accessibilitySettingsURL) }
                }
            } label: {
                Text("Needs Accessibility in System Settings › Privacy & Security. Until then window mode selects whole "
                     + "windows. A rebuilt or moved copy of the app has to be allowed again.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Turning it on asks for the permission at once, while the user is looking at it (never during a capture, where
    /// the question would be hidden behind the capture screen).
    private var enabled: Binding<Bool> {
        Binding(get: { store.value.windowCaptureSelectsAreas },
                set: { on in
                    store.update { $0.windowCaptureSelectsAreas = on }
                    if on && !Permissions.hasAccessibility { Permissions.requestAccessibility() }
                    accessibility.refresh()
                })
    }
}

/// HDR screens (upstream tone maps HDR captures since 1.4, `HdrContent`): bright parts of HDR videos and photos are tone
/// mapped instead of cut off. ScreenCaptureKit captures HDR from macOS 15 on.
struct HDRSetting: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        if #available(macOS 15, *) {
            Toggle("Tone map HDR content on HDR screens", isOn: store.binding(\.toneMapHDRCaptures))
                .help("While an HDR video, photo or game shows, its bright parts keep their detail in the screenshot instead "
                      + "of being cut off. Captures without HDR content keep their colours exactly. Apple silicon only.")
                .managed(\.toneMapHDRCaptures)
        } else {
            Toggle("Tone map HDR content on HDR screens (macOS 15 or later)", isOn: .constant(false))
                .disabled(true)
        }
    }
}

/// How see-through the zoomer is (upstream `ZoomerOpacity`, only in greenshot.ini there; the Mac has no ini file).
private struct ZoomerOpacitySetting: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        LabeledContent("Zoomer opacity") {
            HStack {
                Slider(value: store.binding(\.zoomerOpacity), in: 0.1...1)
                    .frame(width: 160)
                Text("\(Int((store.value.zoomerOpacity * 100).rounded())) %").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
        .disabled(!store.value.zoomerEnabled)
        .help("Below 100 % the screen shows through the zoomer.")
        .managed(\.zoomerOpacity)
    }
}

/// The sound after a capture (upstream `NotificationSound`): the camera sound of macOS, or a sound file.
private struct CameraSoundSetting: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        LabeledContent("Sound") {
            HStack {
                Text(name).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Button {
                    CameraSound.play(file: store.value.notificationSound)
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Play the sound")
                Button("Choose…", action: choose)
                if !store.value.notificationSound.isEmpty {
                    Button("Default") { store.update { $0.notificationSound = "" } }
                }
            }
        }
        .disabled(!store.value.playCameraSound)
        .managed(\.notificationSound)
    }

    private var name: String {
        guard let url = CameraSound.url(of: store.value.notificationSound) else { return "Camera (macOS)" }
        return FileManager.default.fileExists(atPath: url.path) ? url.lastPathComponent : "\(url.lastPathComponent) (missing, the camera plays)"
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.directoryURL = CameraSound.url(of: store.value.notificationSound)?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
        panel.message = "Choose the sound to play after a capture."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.update { $0.notificationSound = url.path }
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
            .managed(\.screenCaptureMode)
            if store.value.screenCaptureMode == .fixed {
                Stepper(value: store.binding(\.screenToCapture), in: 1...9) {
                    Text("Screen \(store.value.screenToCapture)\(screenName)")
                }
                .managed(\.screenToCapture)
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
                .managed(\.fixedCaptureSizes)
            }
            HStack {
                TextField("Size", text: $draft.text, prompt: Text("1280x720"))
                    .onSubmit(add)
                Button("Add", action: add).disabled(newSizes.isEmpty)
            }
            .managed(\.fixedCaptureSizes)
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
            Toggle("Recognise the text as soon as the capture screen opens", isOn: store.binding(\.alwaysRunOCROnCapture))
                .help("The lines are then ready when you press T. Upstream: AlwaysRunOCROnCapture.")
                .managed(\.alwaysRunOCROnCapture)
            Picker("Language of the text", selection: store.binding(\.ocrLanguage)) {
                Text("Automatic").tag("")
                ForEach(Self.languages, id: \.self) { Text(Self.name(of: $0)).tag($0) }
                if !store.value.ocrLanguage.isEmpty && !Self.languages.contains(store.value.ocrLanguage) {
                    Text(store.value.ocrLanguage).tag(store.value.ocrLanguage)
                }
            }
            .managed(\.ocrLanguage)
        }
    }

    private static func name(of code: String) -> String {
        Locale.current.localizedString(forIdentifier: code).map { "\($0) (\(code))" } ?? code
    }
}

/// Upstream `NotificationLevel`. "None" also turns off "Show a message after saving or copying".
