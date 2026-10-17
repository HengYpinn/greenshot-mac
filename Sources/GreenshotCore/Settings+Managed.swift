// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The names of the settings an administrator can set (`ManagedPolicy`): each name is the setting's key in the settings
/// JSON, a member of a group joined with a dot ("printing.footer"). The table also maps the settings' key paths to their
/// names, for `.managed(\.keyPath)` on a settings control (Swift can't name a key path by itself).
///
/// A new setting needs a line here; `ManagedPolicyTests` names a setting that has none. A group is a settings struct
/// whose members an administrator can set one by one; each member needs its own line.
public enum ManagedSettingKeys {
    /// The name of the setting at `keyPath`, nil for a key path the table doesn't have.
    public static func name(for keyPath: AnyKeyPath) -> String? {
        table.names[keyPath]
    }

    /// Whether `path` is a group: a dictionary for it sets the members given.
    public static func isGroup(_ path: String) -> Bool {
        table.groups.contains(path)
    }

    /// Whether `path` names a setting or a group.
    public static func contains(_ path: String) -> Bool {
        table.all.contains(path)
    }

    /// Every name, top-level settings first, in the order of the table.
    public static var names: [String] {
        table.ordered
    }

    struct Table {
        var names: [AnyKeyPath: String] = [:]
        var ordered: [String] = []
        var all: Set<String> = []
        var groups: Set<String> = []

        mutating func add(_ name: String, _ keyPath: PartialKeyPath<AppSettings>) {
            names[keyPath] = name
            ordered.append(name)
            all.insert(name)
        }

        mutating func group(_ name: String, _ keyPath: PartialKeyPath<AppSettings>) {
            add(name, keyPath)
            groups.insert(name)
        }
    }

    private static let table: Table = {
        var t = Table()
        addTopLevel(to: &t)
        addHotkeys(to: &t)
        addOffice(to: &t)
        addVideo(to: &t)
        addRecipes(to: &t)
        addAITools(to: &t)
        addDropShadowSettings(to: &t)
        addTornEdgeSettings(to: &t)
        addTextObfuscation(to: &t)
        addPrinting(to: &t)
        addEmail(to: &t)
        addPdf(to: &t)
        addJira(to: &t)
        addConfluence(to: &t)
        addBox(to: &t)
        addDropbox(to: &t)
        return t
    }()

    // Statement by statement: one big literal is too slow for the type checker of Swift 6.1.
    private static func addTopLevel(to t: inout Table) {
        t.group("hotkeys", \AppSettings.hotkeys)
        t.add("destinations", \AppSettings.destinations)
        t.add("captureMousePointer", \AppSettings.captureMousePointer)
        t.add("interactiveWindowCapture", \AppSettings.interactiveWindowCapture)
        t.add("includeWindowShadow", \AppSettings.includeWindowShadow)
        t.add("captureDelayMilliseconds", \AppSettings.captureDelayMilliseconds)
        t.add("windowCaptureSelectsAreas", \AppSettings.windowCaptureSelectsAreas)
        t.add("toneMapHDRCaptures", \AppSettings.toneMapHDRCaptures)
        t.add("showNotificationThumbnail", \AppSettings.showNotificationThumbnail)
        t.add("welcomeShown", \AppSettings.welcomeShown)
        t.group("office", \AppSettings.office)
        t.add("allowedUntrustedCertificateHosts", \AppSettings.allowedUntrustedCertificateHosts)
        t.add("allowedCertificateThumbprints", \AppSettings.allowedCertificateThumbprints)
        t.group("video", \AppSettings.video)
        t.group("recipes", \AppSettings.recipes)
        t.add("automationAllowCaptureLinks", \AppSettings.automationAllowCaptureLinks)
        t.group("aiTools", \AppSettings.aiTools)
        t.add("browserExtensionEnabled", \AppSettings.browserExtensionEnabled)
        t.add("disableSettings", \AppSettings.disableSettings)
        t.add("disableQuickSettings", \AppSettings.disableQuickSettings)
        t.add("hideExpertSettings", \AppSettings.hideExpertSettings)
        t.add("excludeDestinations", \AppSettings.excludeDestinations)
        t.add("playCameraSound", \AppSettings.playCameraSound)
        t.add("notificationSound", \AppSettings.notificationSound)
        t.add("showNotifications", \AppSettings.showNotifications)
        t.add("dockIconWhileWindowOpen", \AppSettings.dockIconWhileWindowOpen)
        t.add("zoomerEnabled", \AppSettings.zoomerEnabled)
        t.add("outputFolder", \AppSettings.outputFolder)
        t.add("filenamePattern", \AppSettings.filenamePattern)
        t.add("outputFormat", \AppSettings.outputFormat)
        t.add("jpegQuality", \AppSettings.jpegQuality)
        t.add("copyPathToClipboard", \AppSettings.copyPathToClipboard)
        t.add("incrementingNumber", \AppSettings.incrementingNumber)
        t.add("lastCapturedRegion", \AppSettings.lastCapturedRegion)
        t.add("editorStyles", \AppSettings.editorStyles)
        t.add("recentEmoji", \AppSettings.recentEmoji)
        t.add("fixedCaptureSizes", \AppSettings.fixedCaptureSizes)
        t.add("recentCaptureSizes", \AppSettings.recentCaptureSizes)
        t.add("fixedCaptureSize", \AppSettings.fixedCaptureSize)
        t.add("fixedCaptureAnchor", \AppSettings.fixedCaptureAnchor)
        t.add("screenCaptureMode", \AppSettings.screenCaptureMode)
        t.add("screenToCapture", \AppSettings.screenToCapture)
        t.add("captureHelpVisible", \AppSettings.captureHelpVisible)
        t.add("captureInfoVisible", \AppSettings.captureInfoVisible)
        t.add("captureSelectionPreviewVisible", \AppSettings.captureSelectionPreviewVisible)
        t.add("zoomerShowsPreview", \AppSettings.zoomerShowsPreview)
        t.add("zoomerOpacity", \AppSettings.zoomerOpacity)
        t.add("ocrLanguage", \AppSettings.ocrLanguage)
        t.add("alwaysRunOCROnCapture", \AppSettings.alwaysRunOCROnCapture)
        t.add("scanQRCodesOnCapture", \AppSettings.scanQRCodesOnCapture)
        t.add("autoCropDifference", \AppSettings.autoCropDifference)
        t.add("notificationLevel", \AppSettings.notificationLevel)
        t.add("reuseEditor", \AppSettings.reuseEditor)
        t.add("suppressSaveDialogAtClose", \AppSettings.suppressSaveDialogAtClose)
        t.add("matchSizeToCapture", \AppSettings.matchSizeToCapture)
        t.group("dropShadowSettings", \AppSettings.dropShadowSettings)
        t.group("tornEdgeSettings", \AppSettings.tornEdgeSettings)
        t.group("textObfuscation", \AppSettings.textObfuscation)
        t.add("cutOutMarkStyle", \AppSettings.cutOutMarkStyle)
        t.add("freehandSensitivity", \AppSettings.freehandSensitivity)
        t.add("defaultEditorSize", \AppSettings.defaultEditorSize)
        t.add("allowOverwrite", \AppSettings.allowOverwrite)
        t.add("promptJpegQuality", \AppSettings.promptJpegQuality)
        t.add("reduceColors", \AppSettings.reduceColors)
        t.add("reduceColorsTo", \AppSettings.reduceColorsTo)
        t.add("autoReduceColors", \AppSettings.autoReduceColors)
        t.add("clipboardFormats", \AppSettings.clipboardFormats)
        t.group("printing", \AppSettings.printing)
        t.group("email", \AppSettings.email)
        t.add("externalCommands", \AppSettings.externalCommands)
        t.group("pdf", \AppSettings.pdf)
        t.group("jira", \AppSettings.jira)
        t.group("confluence", \AppSettings.confluence)
        t.group("box", \AppSettings.box)
        t.group("dropbox", \AppSettings.dropbox)
        t.add("updateCheckIntervalDays", \AppSettings.updateCheckIntervalDays)
        t.add("lastUpdateCheck", \AppSettings.lastUpdateCheck)
        t.add("lastSavedFile", \AppSettings.lastSavedFile)
        t.add("leftClickAction", \AppSettings.leftClickAction)
        t.add("doubleClickAction", \AppSettings.doubleClickAction)
        t.add("hideMenuBarIcon", \AppSettings.hideMenuBarIcon)
        t.add("thumbnailPreview", \AppSettings.thumbnailPreview)
        t.add("maxMenuItemLength", \AppSettings.maxMenuItemLength)
        t.add("theme", \AppSettings.theme)
        t.add("checkForUnstable", \AppSettings.checkForUnstable)
    }

    private static func addHotkeys(to t: inout Table) {
        t.add("hotkeys.region", \AppSettings.hotkeys.region)
        t.add("hotkeys.window", \AppSettings.hotkeys.window)
        t.add("hotkeys.fullScreen", \AppSettings.hotkeys.fullScreen)
        t.add("hotkeys.lastRegion", \AppSettings.hotkeys.lastRegion)
        t.add("hotkeys.clipboard", \AppSettings.hotkeys.clipboard)
        t.add("hotkeys.text", \AppSettings.hotkeys.text)
        t.add("hotkeys.recordVideo", \AppSettings.hotkeys.recordVideo)
    }

    private static func addOffice(to t: inout Table) {
        t.add("office.outlookEmailFormat", \AppSettings.office.outlookEmailFormat)
        t.add("office.wordLockAspectRatio", \AppSettings.office.wordLockAspectRatio)
        t.add("office.powerpointLockAspectRatio", \AppSettings.office.powerpointLockAspectRatio)
        t.add("office.powerpointSlideLayout", \AppSettings.office.powerpointSlideLayout)
    }

    private static func addVideo(to t: inout Table) {
        t.add("video.format", \AppSettings.video.format)
        t.add("video.preset", \AppSettings.video.preset)
        t.add("video.frameRate", \AppSettings.video.frameRate)
        t.add("video.bitrate", \AppSettings.video.bitrate)
        t.add("video.scaleFactor", \AppSettings.video.scaleFactor)
        t.add("video.maximumSize", \AppSettings.video.maximumSize)
        t.add("video.colorMode", \AppSettings.video.colorMode)
        t.add("video.captureCursor", \AppSettings.video.captureCursor)
        t.add("video.windowResizeBehavior", \AppSettings.video.windowResizeBehavior)
        t.add("video.stopWhenWindowCloses", \AppSettings.video.stopWhenWindowCloses)
        t.add("video.maximumDurationSeconds", \AppSettings.video.maximumDurationSeconds)
        t.add("video.audioSource", \AppSettings.video.audioSource)
        t.add("video.preventSleep", \AppSettings.video.preventSleep)
        t.add("video.autoPauseOnLock", \AppSettings.video.autoPauseOnLock)
        t.add("video.countdownSeconds", \AppSettings.video.countdownSeconds)
        t.add("video.hotkeyTarget", \AppSettings.video.hotkeyTarget)
        t.add("video.outputFolder", \AppSettings.video.outputFolder)
        t.add("video.filenamePattern", \AppSettings.video.filenamePattern)
        t.add("video.destinations", \AppSettings.video.destinations)
    }

    private static func addRecipes(to t: inout Table) {
        t.add("recipes.enabled", \AppSettings.recipes.enabled)
        t.add("recipes.files", \AppSettings.recipes.files)
        t.add("recipes.disabledRecipeIds", \AppSettings.recipes.disabledRecipeIds)
        t.add("recipes.optionValues", \AppSettings.recipes.optionValues)
        t.add("recipes.unloadedRecipes", \AppSettings.recipes.unloadedRecipes)
    }

    private static func addAITools(to t: inout Table) {
        t.add("aiTools.enabled", \AppSettings.aiTools.enabled)
        t.add("aiTools.allowRecipeProposals", \AppSettings.aiTools.allowRecipeProposals)
        t.add("aiTools.allowedClients", \AppSettings.aiTools.allowedClients)
        t.add("aiTools.excludedApplications", \AppSettings.aiTools.excludedApplications)
        t.add("aiTools.notifyOnCapture", \AppSettings.aiTools.notifyOnCapture)
    }

    private static func addDropShadowSettings(to t: inout Table) {
        t.add("dropShadowSettings.darkness", \AppSettings.dropShadowSettings.darkness)
        t.add("dropShadowSettings.size", \AppSettings.dropShadowSettings.size)
        t.add("dropShadowSettings.offsetX", \AppSettings.dropShadowSettings.offsetX)
        t.add("dropShadowSettings.offsetY", \AppSettings.dropShadowSettings.offsetY)
    }

    private static func addTornEdgeSettings(to t: inout Table) {
        t.add("tornEdgeSettings.toothHeight", \AppSettings.tornEdgeSettings.toothHeight)
        t.add("tornEdgeSettings.horizontalToothRange", \AppSettings.tornEdgeSettings.horizontalToothRange)
        t.add("tornEdgeSettings.verticalToothRange", \AppSettings.tornEdgeSettings.verticalToothRange)
        t.add("tornEdgeSettings.top", \AppSettings.tornEdgeSettings.top)
        t.add("tornEdgeSettings.left", \AppSettings.tornEdgeSettings.left)
        t.add("tornEdgeSettings.right", \AppSettings.tornEdgeSettings.right)
        t.add("tornEdgeSettings.bottom", \AppSettings.tornEdgeSettings.bottom)
        t.add("tornEdgeSettings.shadow", \AppSettings.tornEdgeSettings.shadow)
        t.add("tornEdgeSettings.shadowDarkness", \AppSettings.tornEdgeSettings.shadowDarkness)
        t.add("tornEdgeSettings.shadowSize", \AppSettings.tornEdgeSettings.shadowSize)
        t.add("tornEdgeSettings.shadowOffsetX", \AppSettings.tornEdgeSettings.shadowOffsetX)
        t.add("tornEdgeSettings.shadowOffsetY", \AppSettings.tornEdgeSettings.shadowOffsetY)
        t.add("tornEdgeSettings.backgroundColor", \AppSettings.tornEdgeSettings.backgroundColor)
    }

    private static func addTextObfuscation(to t: inout Table) {
        t.add("textObfuscation.searchPattern", \AppSettings.textObfuscation.searchPattern)
        t.add("textObfuscation.useRegex", \AppSettings.textObfuscation.useRegex)
        t.add("textObfuscation.caseSensitive", \AppSettings.textObfuscation.caseSensitive)
        t.add("textObfuscation.scope", \AppSettings.textObfuscation.scope)
        t.add("textObfuscation.effect", \AppSettings.textObfuscation.effect)
        t.add("textObfuscation.paddingHorizontal", \AppSettings.textObfuscation.paddingHorizontal)
        t.add("textObfuscation.paddingVertical", \AppSettings.textObfuscation.paddingVertical)
        t.add("textObfuscation.offsetX", \AppSettings.textObfuscation.offsetX)
        t.add("textObfuscation.offsetY", \AppSettings.textObfuscation.offsetY)
        t.add("textObfuscation.pixelSize", \AppSettings.textObfuscation.pixelSize)
        t.add("textObfuscation.blurRadius", \AppSettings.textObfuscation.blurRadius)
        t.add("textObfuscation.magnification", \AppSettings.textObfuscation.magnification)
        t.add("textObfuscation.highlightColor", \AppSettings.textObfuscation.highlightColor)
    }

    private static func addPrinting(to t: inout Table) {
        t.add("printing.promptOptions", \AppSettings.printing.promptOptions)
        t.add("printing.inverted", \AppSettings.printing.inverted)
        t.add("printing.grayscale", \AppSettings.printing.grayscale)
        t.add("printing.monochrome", \AppSettings.printing.monochrome)
        t.add("printing.monochromeThreshold", \AppSettings.printing.monochromeThreshold)
        t.add("printing.footer", \AppSettings.printing.footer)
        t.add("printing.footerPattern", \AppSettings.printing.footerPattern)
        t.add("printing.allowShrink", \AppSettings.printing.allowShrink)
        t.add("printing.allowEnlarge", \AppSettings.printing.allowEnlarge)
        t.add("printing.allowRotate", \AppSettings.printing.allowRotate)
        t.add("printing.center", \AppSettings.printing.center)
    }

    private static func addEmail(to t: inout Table) {
        t.add("email.to", \AppSettings.email.to)
        t.add("email.cc", \AppSettings.email.cc)
        t.add("email.bcc", \AppSettings.email.bcc)
        t.add("email.subjectPattern", \AppSettings.email.subjectPattern)
    }

    private static func addPdf(to t: inout Table) {
        t.add("pdf.pageSize", \AppSettings.pdf.pageSize)
        t.add("pdf.unit", \AppSettings.pdf.unit)
        t.add("pdf.customWidth", \AppSettings.pdf.customWidth)
        t.add("pdf.customHeight", \AppSettings.pdf.customHeight)
        t.add("pdf.marginTop", \AppSettings.pdf.marginTop)
        t.add("pdf.marginLeft", \AppSettings.pdf.marginLeft)
        t.add("pdf.marginRight", \AppSettings.pdf.marginRight)
        t.add("pdf.marginBottom", \AppSettings.pdf.marginBottom)
        t.add("pdf.scaling", \AppSettings.pdf.scaling)
    }

    private static func addJira(to t: inout Table) {
        t.add("jira.url", \AppSettings.jira.url)
        t.add("jira.email", \AppSettings.jira.email)
        t.add("jira.uploadFormat", \AppSettings.jira.uploadFormat)
        t.add("jira.jpegQuality", \AppSettings.jira.jpegQuality)
        t.add("jira.recentIssueKeys", \AppSettings.jira.recentIssueKeys)
        t.add("jira.reduceColors", \AppSettings.jira.reduceColors)
        t.add("jira.login", \AppSettings.jira.login)
    }

    private static func addConfluence(to t: inout Table) {
        t.add("confluence.url", \AppSettings.confluence.url)
        t.add("confluence.email", \AppSettings.confluence.email)
        t.add("confluence.uploadFormat", \AppSettings.confluence.uploadFormat)
        t.add("confluence.jpegQuality", \AppSettings.confluence.jpegQuality)
        t.add("confluence.openPageAfterUpload", \AppSettings.confluence.openPageAfterUpload)
        t.add("confluence.clipboardContent", \AppSettings.confluence.clipboardContent)
        t.add("confluence.recentPages", \AppSettings.confluence.recentPages)
        t.add("confluence.searchSpaceKey", \AppSettings.confluence.searchSpaceKey)
        t.add("confluence.reduceColors", \AppSettings.confluence.reduceColors)
        t.add("confluence.login", \AppSettings.confluence.login)
        t.add("confluence.includePersonalSpaces", \AppSettings.confluence.includePersonalSpaces)
    }

    private static func addBox(to t: inout Table) {
        t.add("box.clientID", \AppSettings.box.clientID)
        t.add("box.uploadFormat", \AppSettings.box.uploadFormat)
        t.add("box.jpegQuality", \AppSettings.box.jpegQuality)
        t.add("box.folderID", \AppSettings.box.folderID)
        t.add("box.copyLinkToClipboard", \AppSettings.box.copyLinkToClipboard)
        t.add("box.useSharedLink", \AppSettings.box.useSharedLink)
    }

    private static func addDropbox(to t: inout Table) {
        t.add("dropbox.appKey", \AppSettings.dropbox.appKey)
        t.add("dropbox.uploadFormat", \AppSettings.dropbox.uploadFormat)
        t.add("dropbox.jpegQuality", \AppSettings.dropbox.jpegQuality)
        t.add("dropbox.folder", \AppSettings.dropbox.folder)
        t.add("dropbox.copyLinkToClipboard", \AppSettings.dropbox.copyLinkToClipboard)
    }
}

// MARK: Excluded destinations

extension CaptureDestination {
    /// The destinations a name in `excludeDestinations` stands for, any case, spaces, "_" and "-" ignored: the Mac's own
    /// names (`fileAs`), upstream's designations (`FileNoDialog`, `EMail`, `Windows10Share`, `OneNote`, …) and upstream's
    /// plugin names (`Office Plugin` is Word, Excel, PowerPoint, Outlook and Notes); empty for an unknown name.
    public static func excluded(byName name: String) -> [CaptureDestination] {
        let key = name.lowercased().filter { !" _-".contains($0) }
        if let own = allCases.first(where: { $0.rawValue.lowercased() == key }) { return [own] }
        switch key {
        case "filenodialog": return [.file]
        case "filedialog": return [.fileAs]
        case "windows10share": return [.share]
        case "windows10ocr": return [.ocr]
        case "zxingqrdestination", "zxing", "zxingplugin": return [.qrCode]
        case "onenote": return [.notes]
        case "boxplugin": return [.box]
        case "confluenceplugin": return [.confluence]
        case "dropboxplugin": return [.dropbox]
        case "externalcommandplugin": return [.externalCommand]
        case "jiraplugin": return [.jira]
        case "pdfplugin": return [.pdf]
        case "office", "officeplugin": return [.word, .excel, .powerpoint, .outlook, .notes]
        default: return []
        }
    }
}

extension AppSettings {
    /// The destinations `excludeDestinations` turns off (upstream `DestinationBase.IsExcludedByConfiguration`).
    public var excludedDestinations: Set<CaptureDestination> {
        Set(excludeDestinations.flatMap(CaptureDestination.excluded(byName:)))
    }

    /// Whether the destination is turned off: it is left out of every menu and list, and refused.
    public func isDestinationExcluded(_ destination: CaptureDestination) -> Bool {
        !excludeDestinations.isEmpty && excludedDestinations.contains(destination)
    }

    /// The names in `excludeDestinations` that stand for no destination.
    public var unknownExcludedDestinationNames: [String] {
        excludeDestinations.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty && CaptureDestination.excluded(byName: $0).isEmpty
        }
    }

    /// Takes the excluded destinations out of `destinations`; when none is left, the first allowed one of "Ask every
    /// time", the editor, "Save directly" and the clipboard (upstream: an empty `OutputDestinations` gets the picker).
    public mutating func removeExcludedDestinations() {
        guard !excludeDestinations.isEmpty else { return }
        let excluded = excludedDestinations
        guard destinations.contains(where: excluded.contains) else { return }
        destinations.removeAll(where: excluded.contains)
        if destinations.isEmpty {
            let fallback: [CaptureDestination] = [.picker, .editor, .file, .clipboard]
            destinations = fallback.first { !excluded.contains($0) }.map { [$0] } ?? []
        }
    }
}
