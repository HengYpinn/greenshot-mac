// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// Settings › Video: the options of upstream's recipe step "Record Video" (`VideoCaptureOptions.cs`,
/// `RecordVideoRecipeStep.cs`) as the defaults of Record Screen / Window / Region… and the record hotkey.
struct VideoSettingsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            qualitySection
            soundSection
            windowSection
            startStopSection
            filesSection
        }
        .formStyle(.grouped)
    }

    private var video: VideoSettings { store.value.video }

    // MARK: Quality

    private var qualitySection: some View {
        Section("Quality") {
            Picker("Preset", selection: store.binding(\.video.preset)) {
                ForEach(VideoEncodingPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.video.preset)
            if video.preset == .custom {
                Picker("Frame rate", selection: store.binding(\.video.frameRate)) {
                    ForEach(Self.choices([15, 24, 30, 60, 120], including: video.frameRate), id: \.self) { Text("\($0) fps").tag($0) }
                }
                .managed(\.video.frameRate)
                Picker("Bit rate", selection: store.binding(\.video.bitrate)) {
                    ForEach(Self.choices(Self.bitrates, including: video.bitrate), id: \.self) { rate in
                        Text(rate == 0 ? String(localized: "Automatic", comment: "The bit rate of a video, chosen by the app") : VideoBitrateText.text(rate))
                            .tag(rate)
                    }
                }
                .managed(\.video.bitrate)
                Picker("Size", selection: sizeChoice) {
                    ForEach(SizeChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .managed(\.video.scaleFactor, \.video.maximumSize)
                Text("Automatic: at least 1.5 Mbps, more for large or fast videos. A screen gives at most as many frames as it shows.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(video.preset.summary).font(.caption).foregroundStyle(.secondary)
            }
            Picker("Format", selection: store.binding(\.video.format)) {
                ForEach(VideoFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.video.format)
            Picker("Colours", selection: store.binding(\.video.colorMode)) {
                ForEach(VideoColorMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.video.colorMode)
            Toggle("Record the mouse pointer", isOn: store.binding(\.video.captureCursor))
                .managed(\.video.captureCursor)
        }
    }

    /// The size choices of the custom preset: a scale factor or a largest size.
    enum SizeChoice: CaseIterable, Hashable {
        case asRecorded, threeQuarters, half, fit1080, fit720

        var title: String {
            switch self {
            case .asRecorded: return String(localized: "As recorded")
            case .threeQuarters: return "75 %"
            case .half: return "50 %"
            case .fit1080: return String(localized: "At most 1920 × 1080")
            case .fit720: return String(localized: "At most 1280 × 720")
            }
        }

        var values: (scale: Double, maximum: CaptureSize?) {
            switch self {
            case .asRecorded: return (1, nil)
            case .threeQuarters: return (0.75, nil)
            case .half: return (0.5, nil)
            case .fit1080: return (1, CaptureSize(width: 1920, height: 1080))
            case .fit720: return (1, CaptureSize(width: 1280, height: 720))
            }
        }

        init(_ video: VideoSettings) {
            self = Self.allCases.first { choice in
                let values = choice.values
                return values.scale == video.scaleFactor && values.maximum == video.maximumSize
            } ?? .asRecorded
        }
    }

    private var sizeChoice: Binding<SizeChoice> {
        Binding(get: { SizeChoice(store.value.video) },
                set: { choice in
                    store.update { settings in
                        settings.video.scaleFactor = choice.values.scale
                        settings.video.maximumSize = choice.values.maximum
                    }
                })
    }

    static let bitrates = [0, 1_000_000, 2_500_000, 5_000_000, 8_000_000, 15_000_000, 25_000_000]

    // MARK: Sound

    private var soundSection: some View {
        Section("Sound") {
            Picker("Record", selection: store.binding(\.video.audioSource)) {
                ForEach(AudioCaptureSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.video.audioSource)
            if video.audioSource.includesMicrophone {
                Text("macOS asks the first time whether \(AppInfo.name) may use the microphone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Windows

    private var windowSection: some View {
        Section("Windows") {
            Picker("When the window changes size", selection: store.binding(\.video.windowResizeBehavior)) {
                ForEach(WindowResizeBehavior.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.video.windowResizeBehavior)
            Toggle("Stop when the window closes", isOn: store.binding(\.video.stopWhenWindowCloses))
                .managed(\.video.stopWhenWindowCloses)
        }
    }

    // MARK: Starting and stopping

    private var startStopSection: some View {
        Section("Starting and stopping") {
            Picker("Countdown", selection: store.binding(\.video.countdownSeconds)) {
                ForEach(Self.choices([0, 3, 5, 10], including: video.countdownSeconds), id: \.self) { seconds in
                    Text(seconds == 0 ? "None" : "\(seconds) seconds").tag(seconds)
                }
            }
            .managed(\.video.countdownSeconds)
            Picker("Stop after", selection: store.binding(\.video.maximumDurationSeconds)) {
                ForEach(Self.choices([0, 60, 300, 600, 1800, 3600], including: video.maximumDurationSeconds), id: \.self) { seconds in
                    Text(Self.lengthTitle(seconds)).tag(seconds)
                }
            }
            .managed(\.video.maximumDurationSeconds)
            Picker("The hotkey records", selection: store.binding(\.video.hotkeyTarget)) {
                ForEach(RecordingHotkeyTarget.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .managed(\.video.hotkeyTarget)
            Text(hotkeyHint).font(.caption).foregroundStyle(.secondary)
            Toggle("Keep the Mac awake while recording", isOn: store.binding(\.video.preventSleep))
                .managed(\.video.preventSleep)
            Toggle("Pause while the screen is locked", isOn: store.binding(\.video.autoPauseOnLock))
                .managed(\.video.autoPauseOnLock)
        }
    }

    private var hotkeyHint: String {
        let howTo = String(localized: "Set it in General › Hotkeys. A click on the recording's menu bar icon stops it, ⌃-click pauses.")
        guard let combo = store.value.hotkeys.recordVideo else { return howTo }
        let keys = BidiText.isolatedLTR(combo.displayString)
        return String(localized: "The hotkey \(keys) starts and stops a recording.") + " " + howTo
    }

    static func choices(_ common: [Int], including current: Int) -> [Int] {
        common.contains(current) ? common : (common + [current]).sorted()
    }

    static func lengthTitle(_ seconds: Int) -> String {
        if seconds == 0 { return String(localized: "Never", comment: "A recording doesn't stop after a time") }
        if seconds % 3600 == 0 {
            let hours = seconds / 3600
            return hours == 1 ? String(localized: "1 hour") : String(localized: "\(hours) hours")
        }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? String(localized: "1 minute") : String(localized: "\(minutes) minutes")
        }
        return String(localized: "\(seconds) seconds")
    }

    // MARK: Files

    private var filesSection: some View {
        Section("Files") {
            LabeledContent("Folder") {
                HStack {
                    Text(folderText).lineLimit(1).truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
            }
            .managed(\.video.outputFolder)
            TextField("File name pattern", text: store.binding(\.video.filenamePattern))
                .managed(\.video.filenamePattern)
            Text("Example: \(example)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            LabeledContent("After a recording") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(VideoDestination.allCases, id: \.self) { destination in
                        Toggle(destination.displayName, isOn: destinationBinding(destination))
                    }
                }
            }
            .managed(\.video.destinations)
        }
    }

    private var folderText: String {
        let folder = video.outputFolder.trimmingCharacters(in: .whitespaces)
        return folder.isEmpty ? RecordingOutputPath.defaultFolder : folder
    }

    private var example: String {
        let context = store.patternContext(title: "Safari", date: Date(), consumeNumber: false)
        return FilenamePattern.fill(video.filenamePattern, context: context) + "." + RecordingOutputPath.fileExtension
    }

    private func destinationBinding(_ destination: VideoDestination) -> Binding<Bool> {
        Binding(get: { store.value.video.destinations.contains(destination) },
                set: { on in store.update { $0.video.setDestination(destination, on: on) } })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        let current = (folderText as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.update { $0.video.outputFolder = (url.path as NSString).abbreviatingWithTildeInPath }
    }
}
