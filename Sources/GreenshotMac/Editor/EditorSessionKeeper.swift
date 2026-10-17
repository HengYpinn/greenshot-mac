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
/// - While an editor has unsaved changes, it is written 5 seconds after its last change (off the main thread), so a
///   crash or a forced quit loses at most those seconds. Its file goes when it is saved, closed or its changes are
///   discarded.
/// - At a logout, restart or shut down, or when "Close windows when quitting an application" is off, quitting writes
///   every unsaved editor instead of asking about each (asking would cancel the logout).
/// - At the next start the kept editors open again, still unsaved.
@MainActor
final class EditorSessionKeeper {
    static let autosaveDelay: TimeInterval = 5

    let store: EditorSessionStore
    private let queue = DispatchQueue(label: "Greenshot unsaved editors", qos: .utility)
    /// The change count written (or about to be) for each document that has a file.
    private var written: [UUID: Int] = [:]
    private var pending: [UUID: DispatchWorkItem] = [:]
    private var poweringOffSince: Date?
    private var powerOffObserver: NSObjectProtocol?
    private let log = Log("Unsaved editors")

    init(store: EditorSessionStore) {
        self.store = store
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

    /// After a change of the document's image, elements or saved state.
    func documentChanged(_ document: EditorDocument) {
        guard document.isModified else {
            forget(document.id)
            return
        }
        guard written[document.id] != document.changeCount, pending[document.id] == nil else { return }
        let item = DispatchWorkItem { [weak self, weak document] in
            MainActor.assumeIsolated {
                guard let self, let document else { return }
                self.pending[document.id] = nil
                self.write(document, reason: .autosave)
            }
        }
        pending[document.id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autosaveDelay, execute: item)
    }

    /// The editor closed or its changes were saved or discarded: its file goes.
    func forget(_ id: UUID) {
        pending.removeValue(forKey: id)?.cancel()
        guard written.removeValue(forKey: id) != nil else { return }
        let store = store
        queue.async { store.remove(id) }
    }

    /// Writes the document now; `wait` until it is on disk (at quit).
    private func write(_ document: EditorDocument, reason: GreenshotFile.Session.Reason, wait: Bool = false) {
        pending.removeValue(forKey: document.id)?.cancel()
        guard document.isModified else {
            forget(document.id)
            return
        }
        let session = GreenshotFile.Session(reason: reason, originalFile: document.fileURL?.path,
                                            isWindowsGreenshotFile: document.isWindowsGreenshotFile)
        let contents = GreenshotFile.Contents(of: document, session: session)
        let id = document.id
        written[id] = document.changeCount
        let store = store
        let log = log
        let work: @Sendable () -> Void = {
            do {
                try store.write(try contents.encoded(), for: id)
            } catch {
                log.error("Keeping an unsaved editor failed", error: error)
            }
        }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
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

    /// Writes every unsaved document for the next start and waits until they are on disk.
    func keep(_ documents: [EditorDocument]) {
        for document in documents where document.isModified {
            write(document, reason: .quit, wait: true)
        }
        log.info("Kept \(documents.filter(\.isModified).count) unsaved editors for the next start")
    }

    /// Every editor was saved or discarded: nothing is kept. Waits until the files are gone.
    func forgetAll() {
        for item in pending.values { item.cancel() }
        pending.removeAll()
        written.removeAll()
        let store = store
        queue.sync { store.removeAll() }
    }

    // MARK: Next start

    /// A kept editor that was read for restoring, with its file (renamed while it opens).
    struct Kept {
        let contents: GreenshotFile.Contents
        let file: URL
    }

    /// The kept editors, the oldest first. A file whose restore didn't finish last time (the app ended while it
    /// opened) goes to the Trash instead, so it can't end every start the same way.
    func keptFiles() -> [URL] {
        let unfinished = store.unfinishedRestores()
        if !unfinished.isEmpty {
            log.warn("\(unfinished.count) unsaved editors did not finish opening last time, they go to the Trash")
            NSWorkspace.shared.recycle(unfinished) { [log] _, error in
                if let error { log.error("Moving unfinished restores to the Trash failed", error: error) }
            }
        }
        return store.saved()
    }

    /// Claims a kept editor for restoring (renamed while it opens) and reads it; nil when it can't be read (it is
    /// removed then).
    func claim(_ url: URL) -> Kept? {
        guard let claimed = store.claim(url) else { return nil }
        guard let contents = GreenshotFile.read(contentsOf: claimed), contents.session != nil else {
            log.error("A kept editor could not be read: \(url.lastPathComponent)")
            try? FileManager.default.removeItem(at: claimed)
            return nil
        }
        return Kept(contents: contents, file: claimed)
    }

    /// The restored editor's document keeps the file it came from until it is written again, saved or closed.
    func adopt(_ kept: Kept, for document: EditorDocument) {
        if store.adopt(kept.file, as: document.id) {
            written[document.id] = document.changeCount
        } else {
            try? FileManager.default.removeItem(at: kept.file)
        }
    }
}
