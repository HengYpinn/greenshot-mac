// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What this run of the app keeps in an `EditorSessionStore`: which documents have a file there, which change of each
/// is on disk, and which restored ones are not settled yet. The files are written and removed in order on a background
/// queue; the app's `EditorSessionKeeper` decides when.
@MainActor
public final class EditorSessionBook {
    public let store: EditorSessionStore
    private let queue = DispatchQueue(label: "Greenshot unsaved editors", qos: .utility)
    /// Documents of this run that may have a file in the store.
    private var filed: Set<UUID> = []
    /// The change count on disk (or being written) for each document.
    private var written: [UUID: Int] = [:]
    /// Restored documents whose file is still `.restoring`.
    private var unsettled: Set<UUID> = []
    private let log = Log("Unsaved editors")

    public init(store: EditorSessionStore) {
        self.store = store
    }

    /// Whether the document has unsaved changes that are not on disk yet.
    public func needsWrite(_ document: EditorDocument) -> Bool {
        document.isModified && written[document.id] != document.changeCount
    }

    /// Whether the document has a file in the store (as far as this run knows).
    public func hasFile(_ id: UUID) -> Bool {
        filed.contains(id)
    }

    /// Writes the document with its session; a document without unsaved changes loses its file instead. With `wait`
    /// the write is done when this returns, and the result says whether it worked.
    @discardableResult
    public func write(_ document: EditorDocument, reason: GreenshotFile.Session.Reason, wait: Bool = false) -> Bool {
        guard document.isModified else {
            forget(document.id)
            return true
        }
        let session = GreenshotFile.Session(reason: reason, originalFile: document.fileURL?.path,
                                            savesToNewFile: document.savesToNewFile)
        let contents = GreenshotFile.Contents(of: document, session: session)
        let id = document.id
        written[id] = document.changeCount
        filed.insert(id)
        unsettled.remove(id)
        let store = store
        let log = log
        if wait {
            let succeeded = queue.sync { () -> Bool in
                do {
                    try store.write(try contents.encoded(), for: id)
                    return true
                } catch {
                    log.error("Keeping an unsaved editor failed", error: error)
                    return false
                }
            }
            return succeeded
        }
        queue.async {
            do {
                try store.write(try contents.encoded(), for: id)
            } catch {
                log.error("Keeping an unsaved editor failed", error: error)
            }
        }
        return true
    }

    /// The document was saved, closed or its changes discarded: its file goes.
    public func forget(_ id: UUID) {
        written[id] = nil
        unsettled.remove(id)
        guard filed.remove(id) != nil else { return }
        let store = store
        queue.async { store.remove(id) }
    }

    /// Every editor was saved or discarded: none of this run's files is kept (another running copy's files stay).
    /// Done when this returns.
    public func forgetAll() {
        let ids = filed
        filed.removeAll()
        written.removeAll()
        unsettled.removeAll()
        let store = store
        queue.sync { store.remove(ids) }
    }

    /// The restored document keeps the file it was restored from (`claimed`), unsettled. False when that failed.
    public func adopt(_ claimed: URL, for document: EditorDocument) -> Bool {
        guard store.adopt(claimed, as: document.id) else { return false }
        written[document.id] = document.changeCount
        filed.insert(document.id)
        unsettled.insert(document.id)
        return true
    }

    /// The app ran for a while with the restored documents open: their files are kept editors again.
    public func settle() {
        let ids = unsettled
        unsettled.removeAll()
        let store = store
        queue.async {
            for id in ids { store.settle(id) }
        }
    }

    /// Waits for the writes and removals asked for so far.
    public func waitForDisk() {
        queue.sync {}
    }
}
