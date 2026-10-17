// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// An upstream destination designation in a recipe ("Editor", "FileNoDialog", "External MS Paint", "Jira") and the
/// Mac destination it means. Designations are case-insensitive; the Mac-only ones are named after `CaptureDestination`.
public struct RecipeDestinationDesignation: Sendable, Equatable {
    public var designation: String
    public var destination: CaptureDestination?
    /// For "External <name>": the external command of the settings.
    public var externalCommandName: String?

    public init(_ designation: String) {
        let trimmed = designation.trimmingCharacters(in: .whitespaces)
        self.designation = trimmed
        if trimmed.lowercased().hasPrefix("external ") {
            self.destination = .externalCommand
            self.externalCommandName = String(trimmed.dropFirst("external ".count)).trimmingCharacters(in: .whitespaces)
            return
        }
        self.externalCommandName = nil
        let key = trimmed.lowercased()
        self.destination = Self.aliases[key] ?? CaptureDestination.allCases.first { recipeEquals($0.rawValue, trimmed) }
    }

    /// Upstream designations (`WellKnownDestinations`, the plug-in destinations' `Designation`) and the names the docs
    /// use, lowercased.
    private static let aliases: [String: CaptureDestination] = [
        "picker": .picker, "editor": .editor, "clipboard": .clipboard,
        "filenodialog": .file, "file": .file, "savefile": .file,
        "filedialog": .fileAs, "fileas": .fileAs,
        "printer": .printer, "email": .email, "mail": .email,
        "windows10share": .share, "share": .share,
        "windows10ocr": .ocr, "ocr": .ocr,
        "zxingqrdestination": .qrCode, "qrcode": .qrCode,
        "pdf": .pdf, "openwith": .openWith,
        "word": .word, "excel": .excel, "powerpoint": .powerpoint, "outlook": .outlook, "onenote": .notes, "notes": .notes,
        "jira": .jira, "confluence": .confluence, "box": .box, "dropbox": .dropbox
    ]
    /// The designation upstream uses for a Mac destination ("FileNoDialog" for `.file`).
    public static func designation(for destination: CaptureDestination) -> String {
        switch destination {
        case .picker: return "Picker"
        case .editor: return "Editor"
        case .clipboard: return "Clipboard"
        case .file: return "FileNoDialog"
        case .fileAs: return "FileDialog"
        case .printer: return "Printer"
        case .email: return "EMail"
        case .share: return "Windows10Share"
        case .ocr: return "Windows10OCR"
        case .externalCommand: return "External"
        case .pdf: return "Pdf"
        case .openWith: return "OpenWith"
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "Powerpoint"
        case .outlook: return "Outlook"
        case .notes: return "OneNote"
        case .qrCode: return "ZxingQrDestination"
        case .jira: return "Jira"
        case .confluence: return "Confluence"
        case .box: return "Box"
        case .dropbox: return "Dropbox"
        }
    }
    /// Uploads (Jira, Confluence, Box, Dropbox) and external commands; nil for the others (upstream's destinations'
    /// `GetGatedActions`).
    public func gatedAction(_ environment: GateEnvironment) -> RecipeGatedAction? {
        switch destination {
        case .jira?: return RecipeGatedAction(.networkAccess, target: "Jira")
        case .confluence?: return RecipeGatedAction(.networkAccess, target: "Confluence")
        case .box?: return RecipeGatedAction(.networkAccess, target: "Box (box.com)")
        case .dropbox?: return RecipeGatedAction(.networkAccess, target: "Dropbox (dropbox.com)")
        case .externalCommand?:
            let name = externalCommandName ?? ""
            let commandLine = name.isEmpty ? nil : environment.commandLine(name)
            return RecipeGatedAction(.externalCommand, target: commandLine.map { $0.isEmpty ? designation : $0 } ?? designation)
        default:
            return nil
        }
    }
    /// For the describer: "Open in image editor (Editor)".
    public var displayName: String {
        guard let destination else { return designation }
        if destination == .externalCommand, let name = externalCommandName, !name.isEmpty {
            return "External command \(name) (\(designation))"
        }
        return recipeEquals(destination.displayName, designation) ? designation : "\(destination.displayName) (\(designation))"
    }
}
