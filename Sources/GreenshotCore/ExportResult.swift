// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What became of a capture sent to a destination (upstream `Greenshot.Base/Interfaces/ExportResult.cs`).
public struct ExportResult: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case succeeded
        /// The user said no (closed a dialog): nothing to tell.
        case declined
        case failed
    }

    public var status: Status
    /// The file the capture was written to (upstream `FilePath`).
    public var fileURL: URL?
    /// The link to the uploaded capture (upstream `Uri`).
    public var link: URL?
    /// What received the capture when it isn't the destination itself, e.g. the Jira issue (upstream `Target`).
    public var target: String?
    /// Why it failed (upstream `Error`).
    public var error: String?
    /// A successful export counts as saved: the editor's unsaved-changes mark goes (upstream `ClearsModified`).
    public var clearsModified: Bool

    public init(status: Status, fileURL: URL? = nil, link: URL? = nil, target: String? = nil, error: String? = nil,
                clearsModified: Bool = true) {
        self.status = status
        self.fileURL = fileURL
        self.link = link
        self.target = target
        self.error = error
        self.clearsModified = clearsModified
    }

    public var isSucceeded: Bool { status == .succeeded }

    public static func succeeded(fileURL: URL? = nil, link: URL? = nil, target: String? = nil,
                                 clearsModified: Bool = true) -> ExportResult {
        ExportResult(status: .succeeded, fileURL: fileURL, link: link, target: target, clearsModified: clearsModified)
    }

    public static let declined = ExportResult(status: .declined, clearsModified: false)

    public static func failed(_ error: String, target: String? = nil) -> ExportResult {
        ExportResult(status: .failed, target: target, error: error, clearsModified: false)
    }
}
