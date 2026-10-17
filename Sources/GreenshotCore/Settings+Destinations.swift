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
        case .cloudAPIToken: return "Cloud: email and API token"
        case .serverToken: return "Server or Data Center: personal access token"
        case .serverPassword: return "Server or Data Center: user name and password"
        }
    }

    /// The label of the user field; nil when the login has none (a personal access token).
    public var userLabel: String? {
        switch self {
        case .cloudAPIToken: return "Email"
        case .serverToken: return nil
        case .serverPassword: return "User name"
        }
    }

    /// The label of the secret, which is kept in the Keychain.
    public var secretLabel: String {
        switch self {
        case .cloudAPIToken: return "API token"
        case .serverToken: return "Personal access token"
        case .serverPassword: return "Password"
        }
    }
}

/// Upstream Office plugin settings (`IOfficeConfiguration.cs`). To, CC, BCC and the subject pattern are `EmailSettings`'
/// (upstream keeps a second set for Outlook).
public struct OfficeSettings: Codable, Equatable, Sendable {
    /// Upstream `EmailFormat`: the body of a new Outlook mail.
    public enum EmailFormat: String, Codable, CaseIterable, Sendable {
        case html, text

        public var displayName: String { self == .html ? "HTML" : "Text" }
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

        /// "Picture with caption" etc.
        public var displayName: String {
            switch self {
            case .title: return "Title"
            case .text: return "Text"
            case .textAndMediaClip: return "Text and media clip"
            default:
                let text = words
                return text.prefix(1).uppercased() + text.dropFirst()
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
