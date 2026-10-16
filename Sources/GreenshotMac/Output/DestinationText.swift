// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// "Copy text (OCR)": the text in the screenshot to the clipboard. Port of upstream
/// `Greenshot/Destinations/Win10OcrDestination.cs`, with the Vision framework instead of Windows OCR.
@MainActor
enum TextDestination {
    static func copyText(_ capture: Capture, settings: SettingsStore, saver: ImageSaver) {
        let image = capture.image
        let language = settings.value.ocrLanguage
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try TextRecognizer.recognizeText(in: image, language: language) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { finish(result, saver: saver) }
            }
        }
    }

    private static func finish(_ result: Result<String, Error>, saver: ImageSaver) {
        switch result {
        case .failure(let error):
            ErrorPresenter.show(error, title: "The text could not be recognised")
        case .success(let text):
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).count
            guard lines > 0 else {
                saver.notify("No text found", detail: "The clipboard was left as it was.", kind: .warning)
                return
            }
            Clipboard.copy(text: text)
            saver.notify(lines == 1 ? "Copied 1 line of text" : "Copied \(lines) lines of text",
                         detail: String(text.prefix(80)))
        }
    }
}
