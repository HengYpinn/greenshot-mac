// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore

/// Keeps unsaved editors for the next start: the macOS counterpart of upstream's Restart Manager integration
/// (`Greenshot/Helpers/RestartManagerHelper.cs`: `SaveEditorState` when Windows ends the session, `RestoreState` with
/// `--restore`; `ImageEditorForm.TrySaveState` saves only modified editors).
///
/// - While an editor has unsaved changes, it is written at most 5 seconds after a change (off the main thread), so a
///   crash or a forced quit loses at most those seconds. Its file goes when it is saved, closed or its changes are
///   discarded.
/// - At a logout, restart or shut down, or when "Close windows when quitting an application" is off, quitting writes
///   every unsaved editor instead of asking about each (asking would cancel the logout).
/// - At the next start the kept editors open again, still unsaved.
@MainActor
final class EditorSessionKeeper {
    static let autosaveDelay: TimeInterval = 5
    /// How long a restored editor has to stay open before its file counts as safe to restore again: until then a crash
    /// (e.g. while it is first drawn) sends the file to the Trash at the next start instead of reopening it.
    static let settleDelay: TimeInterval = 30

    let book: EditorSessionBook
    private var store: EditorSessionStore { book.store }
    private var pending: [UUID: DispatchWorkItem] = [:]
    private var poweringOffSince: Date?
    private var powerOffObserver: NSObjectProtocol?
    private let log = Log("Unsaved editors")

    init(store: EditorSessionStore) {
        book = EditorSessionBook(store: store)
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poweringOffSince = Date() }
        }
    }

    /// The store in Application Support, or with `--settings-dir` in that folder.
    static func standard() -> EditorSessionKeeper {
        let options = AppLaunchOptions.parse(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = EditorSessionStore.folder(settingsDirectory: options.settingsDirectory, applicationSupport: support,
                                               bundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.greenshot-mac.GreenshotMac")
        return EditorSessionKeeper(store: EditorSessionStore(folder: folder))
    }

    // MARK: While the app runs

    /// After a change of the document's image, elements or saved state: written in 5 seconds (also while the user keeps
    /// drawing), or its file goes when it has no unsaved changes any more.
    func documentChanged(_ document: EditorDocument) {
        guard document.isModified else {
            forget(document.id)
            return
        }
        guard book.needsWrite(document), pending[document.id] == nil else { return }
        let item = DispatchWorkItem { [weak self, weak document] in
            MainActor.assumeIsolated {
                guard let self, let document else { return }
                self.pending[document.id] = nil
                self.book.write(document, reason: .autosave)
            }
        }
        pending[document.id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: item)
    }

    /// The editor closed or its changes were saved or discarded: its file goes.
    func forget(_ id: UUID) {
        pending.removeValue(forKey: id)?.cancel()
        book.forget(id)
    }

    // MARK: Quitting

    /// Whether this quit keeps the unsaved editors for the next start instead of asking about each: macOS logs out,
    /// restarts or shuts down (the quit Apple Event's reason, or a power off announced in the last minute), or
    /// "Close windows when quitting an application" is off.
    func quitKeepsEditors() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        var reason: UInt32?
        if let event, event.eventClass == EditorSessionPolicy.code("aevt"), event.eventID == EditorSessionPolicy.code("quit") {
            let keyword = AEKeyword(EditorSessionPolicy.code("why?"))
            reason = (event.attributeDescriptor(forKeyword: keyword) ?? event.paramDescriptor(forKeyword: keyword))?.enumCodeValue
        }
        let keepsWindows = UserDefaults.standard.bool(forKey: "NSQuitAlwaysKeepsWindows")
        let keeps = EditorSessionPolicy.keepsEditors(quitReason: reason, poweringOffSince: poweringOffSince, now: Date(),
                                                     keepsWindows: keepsWindows)
        if keeps {
            log.info("Quitting keeps the unsaved editors (reason \(reason.map { String($0, radix: 16) } ?? "none"), "
                     + "power off \(poweringOffSince != nil), keep windows \(keepsWindows))")
        }
        return keeps
    }

    /// Writes every unsaved document for the next start and waits until they are on disk. Returns the documents that
    /// could not be written (the user is asked about those instead).
    func keep(_ documents: [EditorDocument]) -> [EditorDocument] {
        cancelPending()
        let unsaved = documents.filter(\.isModified)
        let failed = unsaved.filter { !book.write($0, reason: .quit, wait: true) }
        log.info("Kept \(unsaved.count - failed.count) unsaved editors for the next start, \(failed.count) failed")
        return failed
    }

    /// Every editor was saved or discarded: nothing is kept. Waits until the files are gone.
    func forgetAll() {
        cancelPending()
        book.forgetAll()
    }

    private func cancelPending() {
        for item in pending.values { item.cancel() }
        pending.removeAll()
    }

    // MARK: Next start

    /// A kept editor that was read for restoring, with its file (renamed while it opens).
    struct Kept {
        let contents: GreenshotFile.Contents
        let file: URL
    }

    /// The kept editors, the oldest first. A file whose restore didn't finish last time (the app ended while it
    /// opened, or in the first seconds after) goes to the Trash instead, so it can't end every start the same way.
    func keptFiles() -> [URL] {
        let unfinished = store.unfinishedRestores(isRunning: Self.isAnotherRunningCopy)
        if !unfinished.isEmpty {
            log.warn("\(unfinished.count) unsaved editors did not finish opening last time, they go to the Trash")
            NSWorkspace.shared.recycle(unfinished) { [log] _, error in
                if let error { log.error("Moving unfinished restores to the Trash failed", error: error) }
            }
        }
        return store.saved(isRunning: Self.isAnotherRunningCopy)
    }

    /// Whether `process` is another copy of this app that runs now (its kept editors are its own).
    static func isAnotherRunningCopy(_ process: Int32) -> Bool {
        guard process != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: process), !app.isTerminated else { return false }
        if let mine = Bundle.main.bundleIdentifier { return app.bundleIdentifier == mine }
        guard let theirs = app.executableURL, let own = Bundle.main.executableURL else { return false }
        return theirs.resolvingSymlinksInPath() == own.resolvingSymlinksInPath()
    }

    /// Claims a kept editor for restoring (renamed while it opens) and reads it; nil when it can't be read (it goes to
    /// the Trash then, where it can still be looked at).
    func claim(_ url: URL) -> Kept? {
        guard let claimed = store.claim(url) else { return nil }
        guard let contents = GreenshotFile.read(contentsOf: claimed), contents.session != nil else {
            log.error("A kept editor could not be read, it goes to the Trash: \(url.lastPathComponent)")
            recycle(claimed)
            return nil
        }
        return Kept(contents: contents, file: claimed)
    }

    /// The restored editor's document keeps the file it came from until it is written again, saved or closed. The
    /// file stays marked as being restored for `settleDelay` seconds (see `settleRestoredEditors`).
    func adopt(_ kept: Kept, for document: EditorDocument) {
        // Opening scheduled a write; the kept file already holds this state.
        pending.removeValue(forKey: document.id)?.cancel()
        if !book.adopt(kept.file, for: document) {
            // Written again from the open editor; the file it came from goes to the Trash.
            log.warn("A restored editor could not keep its file, it is written again")
            recycle(kept.file)
        }
    }

    private func recycle(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.recycle([url]) { [log] _, error in
            if let error { log.error("Moving \(url.lastPathComponent) to the Trash failed", error: error) }
        }
    }

    /// After the restored editors opened: once the app ran `settleDelay` seconds with them, their files are restored
    /// again after a crash.
    func settleRestoredEditors() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            MainActor.assumeIsolated { self?.book.settle() }
        }
    }
}
