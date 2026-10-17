// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import GreenshotCore
import Testing

/// The Clipboard trigger's look at a change (RCP-065, upstream `ClipboardTrigger.OnClipboardUpdateReceivedAsync`).
struct RecipeTriggersClipboardTests {
    @Test func formatNamesAreUpstreamsWhereThereIsOne() {
        let change = RecipeClipboardChange(types: ["public.png", "public.tiff", "com.example.private", "public.png"])
        #expect(change.formats == ["PNG", "TIFF", "com.example.private"])
    }

    @Test func imageTypesAreImages() {
        #expect(RecipeClipboardChange(types: ["public.tiff"]).hasImageType)
        #expect(RecipeClipboardChange(types: ["public.heic"]).hasImageType)
        #expect(!RecipeClipboardChange(types: ["public.utf8-plain-text"]).hasImageType)
    }

    @Test func filesAndHTMLMayHoldAnImage() {
        #expect(RecipeClipboardChange(types: ["public.file-url"]).mayContainImage)
        #expect(RecipeClipboardChange(types: ["public.html", "public.utf8-plain-text"]).mayContainImage)
        #expect(!RecipeClipboardChange(types: ["public.utf8-plain-text"]).mayContainImage)
    }

    @Test func privateAndOwnCopiesAreIgnored() {
        #expect(RecipeClipboardChange(types: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"]).ignoredReason != nil)
        #expect(RecipeClipboardChange(types: ["org.nspasteboard.TransientType", "public.png"]).ignoredReason != nil)
        #expect(RecipeClipboardChange(types: [ElementTransfer.pasteboardType]).ignoredReason != nil)
        #expect(RecipeClipboardChange(types: ["public.png"]).ignoredReason == nil)
    }

    @Test func formatFilterMatchesPartsOfNamesInAnyCase() {
        let change = RecipeClipboardChange(types: ["public.png", "public.tiff"])
        #expect(change.matches(formatFilter: nil))
        #expect(change.matches(formatFilter: " "))
        #expect(change.matches(formatFilter: "png"))
        #expect(change.matches(formatFilter: "JPEG, PNG"))
        #expect(!change.matches(formatFilter: "JPEG"))
    }

    @Test func windowsBitmapNamesMeanTIFF() {
        #expect(RecipeClipboardChange(types: ["public.tiff"]).matches(formatFilter: "DeviceIndependentBitmap"))
        #expect(RecipeClipboardChange(types: ["public.tiff"]).matches(formatFilter: "DIB"))
        #expect(!RecipeClipboardChange(types: ["public.png"]).matches(formatFilter: "Bitmap"))
    }

    @Test func onImageCopiedNeedsAnImage() {
        let text = RecipeClipboardChange(types: ["public.utf8-plain-text"])
        #expect(!RecipeClipboardChange.fires(onImageCopied: true, formatFilter: nil, change: text, containsImage: false))
        #expect(RecipeClipboardChange.fires(onImageCopied: false, formatFilter: nil, change: text, containsImage: false))
        let html = RecipeClipboardChange(types: ["public.html"])
        #expect(RecipeClipboardChange.fires(onImageCopied: true, formatFilter: nil, change: html, containsImage: true))
        #expect(!RecipeClipboardChange.fires(onImageCopied: true, formatFilter: "PNG", change: html, containsImage: true))
    }

    @Test func variablesCarryTheFormats() {
        let variables = RecipeClipboardChange(types: ["public.png", "public.tiff"]).variables
        #expect(variables["Clipboard.Format"] == .string("PNG"))
        #expect(variables["Clipboard.Formats"] == .array([.string("PNG"), .string("TIFF")]))
        #expect(RecipeClipboardChange(types: []).variables["Clipboard.Format"] == .string("Unknown"))
    }
}
