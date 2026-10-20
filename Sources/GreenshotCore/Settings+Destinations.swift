// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

// Settings of the destinations: how Greenshot signs in to Jira and Confluence, and the Office plugin's options
// (upstream `Greenshot.Plugin.Office/IOfficeConfiguration.cs`).

/// How Greenshot signs in to a Jira or Confluence site. Upstream's clients use basic authentication: user and password
/// (Server/Data Center) or email and API token (Cloud); Data Center also takes personal access tokens.
public enum AtlassianLogin: String, Codable, CaseIterable, Sendable {
    /// Atlassian Cloud: the account's email and an API token (Jira REST v3).
    case cloudAPIToken
    /// Server / Data Center: a personal access token, sent as `Authorization: Bearer` (Jira REST v2).
    case serverToken
    /// Server / Data Center: user name and password (basic authentication, Jira REST v2); asked for when not stored.
    case serverPassword

    public var isCloud: Bool { self == .cloudAPIToken }

    public var displayName: String {
        switch self {
        case .cloudAPIToken: return String(localized: "Cloud: email and API token")
        case .serverToken: return String(localized: "Server or Data Center: personal access token")
        case .serverPassword: return String(localized: "Server or Data Center: user name and password")
        }
    }

    /// The label of the user field; nil when the login has none (a personal access token).
    public var userLabel: String? {
        switch self {
        case .cloudAPIToken: return String(localized: "login.email", defaultValue: "Email", comment: "Label of the field for the email address of an Atlassian account")
        case .serverToken: return nil
        case .serverPassword: return String(localized: "User name")
        }
    }

    /// The label of the secret, which is kept in the Keychain.
    public var secretLabel: String {
        switch self {
        case .cloudAPIToken: return String(localized: "API token")
        case .serverToken: return String(localized: "Personal access token")
        case .serverPassword: return String(localized: "Password")
        }
    }
}

/// Upstream Office plugin settings (`IOfficeConfiguration.cs`). To, CC, BCC and the subject pattern are `EmailSettings`'
/// (upstream keeps a second set for Outlook).
public struct OfficeSettings: Codable, Equatable, Sendable {
    /// Upstream `EmailFormat`: the body of a new Outlook mail.
    public enum EmailFormat: String, Codable, CaseIterable, Sendable {
        case html, text

        public var displayName: String {
            self == .html ? "HTML" : String(localized: "office.emailFormat.text", defaultValue: "Text", comment: "Format of a new Outlook email: plain text (Settings › Destinations › Office)")
        }
    }

    /// Upstream `PpSlideLayout` without `ppLayoutMixed` (values 1–36, PowerPoint's `slide layout …` enumerators).
    public enum SlideLayout: String, Codable, CaseIterable, Sendable {
        case title, text, twoColumnText, table, textAndChart, chartAndText, orgchart, chart, textAndClipart, clipartAndText
        case titleOnly, blank, textAndObject, objectAndText, largeObject, object, textAndMediaClip, mediaClipAndText
        case objectOverText, textOverObject, textAndTwoObjects, twoObjectsAndText, twoObjectsOverText, fourObjects
        case verticalText, clipartAndVerticalText, verticalTitleAndText, verticalTitleAndTextOverChart, twoObjects
        case objectAndTwoObjects, twoObjectsAndObject, custom, sectionHeader, comparison, contentWithCaption
        case pictureWithCaption

        /// The words after "slide layout " of PowerPoint's AppleScript enumerator (`EPPSlideLayout`, codes 0x00cd0001–24
        /// like upstream's values 1–36).
        public var appleScriptName: String {
            switch self {
            case .title: return "title slide"
            case .text: return "text slide"
            case .textAndMediaClip: return "media clip"
            default: return words
            }
        }

        /// "Picture with caption" etc.: the case name in words, in the app's language.
        public var displayName: String {
            switch self {
            case .title: return String(localized: "Title", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .text: return String(localized: "office.slideLayout.text", defaultValue: "Text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .twoColumnText: return String(localized: "Two column text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .table: return String(localized: "Table", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .textAndChart: return String(localized: "Text and chart", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .chartAndText: return String(localized: "Chart and text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .orgchart: return String(localized: "Orgchart", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .chart: return String(localized: "Chart", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .textAndClipart: return String(localized: "Text and clipart", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .clipartAndText: return String(localized: "Clipart and text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .titleOnly: return String(localized: "Title only", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .blank: return String(localized: "Blank", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .textAndObject: return String(localized: "Text and object", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .objectAndText: return String(localized: "Object and text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .largeObject: return String(localized: "Large object", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .object: return String(localized: "Object", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .textAndMediaClip: return String(localized: "Text and media clip", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .mediaClipAndText: return String(localized: "Media clip and text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .objectOverText: return String(localized: "Object over text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .textOverObject: return String(localized: "Text over object", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .textAndTwoObjects: return String(localized: "Text and two objects", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .twoObjectsAndText: return String(localized: "Two objects and text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .twoObjectsOverText: return String(localized: "Two objects over text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .fourObjects: return String(localized: "Four objects", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .verticalText: return String(localized: "Vertical text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .clipartAndVerticalText: return String(localized: "Clipart and vertical text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .verticalTitleAndText: return String(localized: "Vertical title and text", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .verticalTitleAndTextOverChart: return String(localized: "Vertical title and text over chart", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .twoObjects: return String(localized: "Two objects", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .objectAndTwoObjects: return String(localized: "Object and two objects", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .twoObjectsAndObject: return String(localized: "Two objects and object", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .custom: return String(localized: "office.slideLayout.custom", defaultValue: "Custom", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .sectionHeader: return String(localized: "Section header", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .comparison: return String(localized: "Comparison", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .contentWithCaption: return String(localized: "Content with caption", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            case .pictureWithCaption: return String(localized: "Picture with caption", comment: "A slide layout of PowerPoint (Settings › Destinations › Office)")
            }
        }

        /// The case name in words: `twoColumnText` → "two column text".
        private var words: String {
            var result = ""
            for character in rawValue {
                if character.isUppercase {
                    result += " " + character.lowercased()
                } else {
                    result.append(character)
                }
            }
            return result
        }
    }

    /// `OutlookEmailFormat`, default HTML.
    public var outlookEmailFormat: EmailFormat = .html
    /// `WordLockAspectRatio`: the inserted picture keeps its proportions when resized.
    public var wordLockAspectRatio = true
    /// `PowerpointLockAspectRatio`.
    public var powerpointLockAspectRatio = true
    /// `PowerpointSlideLayout`; the title goes into its first shape and the picture into its second (the picture
    /// placeholder); a layout PowerPoint refuses falls back to blank.
    public var powerpointSlideLayout: SlideLayout = .pictureWithCaption
    /// `OutlookAllowExportInMeetings` (upstream default false): the picker also lists the open meeting windows of Outlook
    /// the user organises, and the picture is attached to the meeting (upstream `OutlookEmailExporter.cs:72,121`).
    public var outlookAllowExportInMeetings = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case outlookEmailFormat, wordLockAspectRatio, powerpointLockAspectRatio, powerpointSlideLayout, outlookAllowExportInMeetings
    }

    /// Every value falls back to its default, so settings written by another version (or an unknown layout) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OfficeSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        outlookEmailFormat = value(.outlookEmailFormat, d.outlookEmailFormat)
        wordLockAspectRatio = value(.wordLockAspectRatio, d.wordLockAspectRatio)
        powerpointLockAspectRatio = value(.powerpointLockAspectRatio, d.powerpointLockAspectRatio)
        powerpointSlideLayout = value(.powerpointSlideLayout, d.powerpointSlideLayout)
        outlookAllowExportInMeetings = value(.outlookAllowExportInMeetings, d.outlookAllowExportInMeetings)
    }
}

extension AppSettings {
    /// Whether Settings › Destinations lists `destination` under "After a capture": an Office one only when its app is
    /// installed (`isInstalled`) or it is chosen already, so a destination whose app went away can still be turned off.
    public func offersDestination(_ destination: CaptureDestination, isInstalled: (OfficeApplication) -> Bool) -> Bool {
        guard let app = OfficeApplication(destination: destination) else { return true }
        return destinations.contains(destination) || isInstalled(app)
    }
}
