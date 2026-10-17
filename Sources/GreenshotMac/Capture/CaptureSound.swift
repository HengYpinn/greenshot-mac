// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The sound after a capture (upstream `Greenshot/Helpers/SoundHelper.cs`): the file of the setting `notificationSound`
/// (upstream `NotificationSound`, there only a .wav; here any file macOS plays), else the camera sound of macOS.
enum CameraSound {
    static let systemSoundPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"

    static func play(file: String = "") {
        sound(file: file)?.play()
    }

    /// The sound of `file`, or the default one when it is empty or can't be read.
    static func sound(file: String) -> NSSound? {
        if let url = url(of: file), let custom = NSSound(contentsOf: url, byReference: true) { return custom }
        return NSSound(contentsOfFile: systemSoundPath, byReference: true) ?? NSSound(named: "Tink")
    }

    static func url(of file: String) -> URL? {
        guard !file.isEmpty else { return nil }
        return URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
    }
}
