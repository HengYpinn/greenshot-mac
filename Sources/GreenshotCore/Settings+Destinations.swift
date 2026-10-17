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
}

/// Upstream Office plugin settings (`IOfficeConfiguration.cs`). To, CC, BCC and the subject pattern are `EmailSettings`'
/// (upstream keeps a second set for Outlook).
public struct OfficeSettings: Codable, Equatable, Sendable {
    /// Upstream `EmailFormat`: the body of a new Outlook mail.
    public enum EmailFormat: String, Codable, CaseIterable, Sendable {
        case html, text
    }

    /// Upstream `PpSlideLayout` without `ppLayoutMixed` (values 1–36, PowerPoint's `slide layout …` enumerators).
    public enum SlideLayout: String, Codable, CaseIterable, Sendable {
        case title, text, twoColumnText, table, textAndChart, chartAndText, orgchart, chart, textAndClipart, clipartAndText
        case titleOnly, blank, textAndObject, objectAndText, largeObject, object, textAndMediaClip, mediaClipAndText
        case objectOverText, textOverObject, textAndTwoObjects, twoObjectsAndText, twoObjectsOverText, fourObjects
        case verticalText, clipartAndVerticalText, verticalTitleAndText, verticalTitleAndTextOverChart, twoObjects
        case objectAndTwoObjects, twoObjectsAndObject, custom, sectionHeader, comparison, contentWithCaption
        case pictureWithCaption
    }

    /// `OutlookEmailFormat`, default HTML.
    public var outlookEmailFormat: EmailFormat = .html
    /// `WordLockAspectRatio`: the inserted picture keeps its proportions when resized.
    public var wordLockAspectRatio = true
    /// `PowerpointLockAspectRatio`.
    public var powerpointLockAspectRatio = true
    /// `PowerpointSlideLayout`; a layout without a caption and a picture placeholder falls back to blank.
    public var powerpointSlideLayout: SlideLayout = .pictureWithCaption

    public init() {}

    enum CodingKeys: String, CodingKey {
        case outlookEmailFormat, wordLockAspectRatio, powerpointLockAspectRatio, powerpointSlideLayout
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
    }
}
