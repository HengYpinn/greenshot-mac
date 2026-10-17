// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

enum CameraSound {
    static func play() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        let sound = NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
        sound?.play()
    }
}
