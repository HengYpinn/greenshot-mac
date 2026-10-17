// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The texts of the editor's status bar (upstream `ImageEditorForm.SurfaceMessageReceived`, `UpdateStatusLabel` and
/// `Greenshot.Base/Core/Export/ExportResultHandler.cs` `GetMessage`).
public enum EditorWindowStatus {
    /// A message of the status bar, before the time is put in front.
    public struct Message: Equatable, Sendable {
        public var text: String
        /// Shown in red with a warning sign.
        public var isError: Bool

        public init(text: String, isError: Bool = false) {
            self.text = text
            self.isError = isError
        }
    }

    /// What an export says, or nil when there is nothing to say (declined, or failed without a reason, like
    /// upstream). A saved file names the file (upstream `editor_imagesaved`: "Image saved to {0}."), any other export
    /// says "Exported to: <target>", where the target is what received the capture or else the destination.
    public static func message(for result: ExportResult, destination: String) -> Message? {
        let target = result.target ?? destinationName(destination)
        switch result.status {
        case .declined:
            return nil
        case .succeeded:
            if result.target == nil, let file = result.fileURL {
                return Message(text: "Image saved to \(abbreviated(file)).")
            }
            return Message(text: "Exported to: \(target)")
        case .failed:
            guard let error = result.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty else { return nil }
            return Message(text: "An error occurred while exporting to \(target): \(error)", isError: true)
        }
    }

    /// The status line: the time, then the message; errors get a warning sign (upstream "<time> - ⚠ <message>").
    public static func line(_ message: Message, time: String) -> String {
        message.isError ? "\(time) - ⚠ \(message.text)" : "\(time) - \(message.text)"
    }

    /// The image size at the left of the status bar (upstream `dimensionsLabel`).
    public static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height)) px"
    }

    /// A destination's menu title as a name in a sentence: without the "…" of a menu item that asks something.
    public static func destinationName(_ title: String) -> String {
        var name = title.trimmingCharacters(in: .whitespaces)
        for ellipsis in ["…", "..."] where name.hasSuffix(ellipsis) { name.removeLast(ellipsis.count) }
        return name
    }

    /// A file path with the home folder as "~".
    public static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
