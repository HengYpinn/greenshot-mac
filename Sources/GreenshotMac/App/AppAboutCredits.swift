// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// The text of the About panel, with what upstream's About window (`Greenshot/Views/AboutWindow.xaml`) says: the
/// license with a link to it, where the source is, where to report bugs, and where Greenshot is hosted.
@MainActor
enum AppAboutCredits {
    static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// The build and the processor it runs on, after the version (upstream shows the bitness).
    static var versionDetail: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [build.map { "build \($0)" }, architecture].compactMap { $0 }.joined(separator: ", ")
    }

    static var architecture: String {
        #if arch(arm64)
        return "Apple silicon"
        #else
        return "Intel"
        #endif
    }

    static func make() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 8
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
                                                   .paragraphStyle: paragraph]
        let text = NSMutableAttributedString()
        func add(_ string: String) {
            text.append(NSAttributedString(string: string, attributes: base))
        }
        func link(_ title: String, _ url: URL) {
            var attributes = base
            attributes[.link] = url
            text.append(NSAttributedString(string: title, attributes: attributes))
        }

        add("""
            An unofficial, community-made macOS port of Greenshot, the free and open source screenshot tool for Windows. \
            It is not affiliated with the Greenshot team or the official Greenshot app in the Mac App Store.

            """)
        link("Source code", AppInfo.repositoryURL)
        add(" · ")
        link("Report a bug", AppInfo.issuesURL)
        add("\nGreenshot: ")
        link("getgreenshot.org", AppInfo.upstreamURL)
        add(" · hosted by ")
        link("GitHub", AppInfo.upstreamSourceURL)
        add("""

            Based on Greenshot, Copyright © 2007-2026 Thomas Braun, Jens Klingen, Robin Krom.
            This program comes with ABSOLUTELY NO WARRANTY. This is free software, and you are welcome to redistribute it \
            under certain conditions: the
            """)
        add(" ")
        link("GNU General Public License version 3", licenseURL)
        add(" or later.")
        return text
    }
}
