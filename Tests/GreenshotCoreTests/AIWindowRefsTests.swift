// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import Testing
@testable import GreenshotCore

/// A clock and a window table the tests move.
final class WindowWorld: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_000_000)
    private var owners: [CGWindowID: pid_t] = [:]

    var now: Date { lock.withLock { time } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time = time.addingTimeInterval(seconds) } }
    func set(_ window: CGWindowID, owner: pid_t?) { lock.withLock { owners[window] = owner } }
    func owner(_ window: CGWindowID) -> pid_t? { lock.withLock { owners[window] } }
}

/// Upstream AiWindowRefsTests.
@Suite struct AIWindowRefsTests {
    private func refs(_ world: WindowWorld) -> AIWindowRefs {
        AIWindowRefs(now: { world.now }, ownerOf: { world.owner($0) })
    }

    @Test func sameWindowKeepsItsIdAndIdsAreNotReused() throws {
        let world = WindowWorld()
        world.set(10, owner: 99)
        world.set(11, owner: 99)
        let refs = refs(world)
        let first = refs.register(scope: "a", window: 10, processID: 99)
        #expect(first == "w1")
        #expect(refs.register(scope: "a", window: 10, processID: 99) == "w1")
        #expect(refs.register(scope: "a", window: 11, processID: 99) == "w2")
        let resolved = try refs.resolve(scope: "a", reference: " W1 ").get()
        #expect(resolved == 10)
    }

    @Test func idsBelongToOneAIToolSession() {
        let world = WindowWorld()
        world.set(10, owner: 99)
        let refs = refs(world)
        let id = refs.register(scope: "a", window: 10, processID: 99)
        let other = refs.resolve(scope: "b", reference: id)
        #expect((try? other.get()) == nil)
        if case .failure(let error) = other { #expect(error.message.contains("is not a current window id")) }
    }

    @Test func expireTenMinutesAfterTheLastListing() {
        let world = WindowWorld()
        world.set(10, owner: 99)
        let refs = refs(world)
        let id = refs.register(scope: "a", window: 10, processID: 99)
        world.advance(9 * 60)
        // Listed again: valid for another ten minutes
        #expect(refs.register(scope: "a", window: 10, processID: 99) == id)
        world.advance(9 * 60)
        #expect((try? refs.resolve(scope: "a", reference: id).get()) == 10)
        world.advance(61)
        #expect((try? refs.resolve(scope: "a", reference: id).get()) == nil)
    }

    @Test func closedOrReusedWindowsFail() {
        let world = WindowWorld()
        world.set(10, owner: 99)
        let refs = refs(world)
        let id = refs.register(scope: "a", window: 10, processID: 99)
        world.set(10, owner: 123)
        let reused = refs.resolve(scope: "a", reference: id)
        if case .failure(let error) = reused {
            #expect(error.message == "The window '\(id)' was closed. " + AIWindowRefs.staleMessage)
        } else {
            Issue.record("A window of another process must not resolve")
        }
        // The number listed again for the new process gets a new id
        let fresh = refs.register(scope: "a", window: 10, processID: 123)
        #expect(fresh != id)
        world.set(10, owner: nil)
        #expect((try? refs.resolve(scope: "a", reference: fresh).get()) == nil)
    }

    @Test func numbersAndEmptyTextAreNotIds() {
        let world = WindowWorld()
        world.set(10, owner: 99)
        let refs = refs(world)
        _ = refs.register(scope: "a", window: 10, processID: 99)
        #expect((try? refs.resolve(scope: "a", reference: "10").get()) == nil)
        #expect((try? refs.resolve(scope: "a", reference: "").get()) == nil)
    }

    @Test func keepsAtMostTwoThousandPerAITool() {
        let world = WindowWorld()
        let refs = refs(world)
        for window in 1...2001 {
            world.set(CGWindowID(window), owner: 1)
            _ = refs.register(scope: "a", window: CGWindowID(window), processID: 1)
            world.advance(0.001)
        }
        // The oldest went
        #expect((try? refs.resolve(scope: "a", reference: "w1").get()) == nil)
        #expect((try? refs.resolve(scope: "a", reference: "w2001").get()) == 2001)
    }
}
