// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Carbon.HIToolbox
import Foundation

/// Which hotkey the keys pressed so far complete, for hotkeys of one or more steps (upstream
/// `Greenshot.Base/Core/HotkeyManager.cs` `MatchHotkey`). The app feeds it every registered key that was pressed; it
/// says when a hotkey is complete, and which keys may come next while one of several steps is half typed.
///
/// Upstream sees every key through a keyboard hook. Carbon's `RegisterEventHotKey` only reports registered keys, so
/// the app registers `pendingChords` for as long as `isPending` is true, and calls `expire(at:)` after
/// `chordTimeout`: a key that doesn't belong to the hotkey can't cancel it, only Esc and the timeout can. Hotkeys that
/// need the left or right key of a modifier come from the app's event tap instead, which sees every key and passes
/// the event's device flags (`feed(_:deviceFlags:at:)`).
public struct HotkeySequenceMatcher: Sendable {
    /// The time allowed between two steps (upstream `ChordTimeout`).
    public static let chordTimeout: TimeInterval = 2.5
    static let escape = KeyChord(keyCode: UInt32(kVK_Escape), modifiers: 0)

    public enum Result: Equatable, Sendable {
        /// The hotkey with this index is complete.
        case completed(Int)
        /// A step of a longer hotkey: waiting for the next one.
        case pending
        /// Esc ended a half typed hotkey.
        case cancelled
        /// The key completes and starts nothing.
        case ignored
    }

    /// The hotkeys, their index is what `completed` reports.
    public let hotkeys: [KeyCombo]
    private var candidates: [Int] = []
    private var step = 0
    private var lastStepAt: Date?

    public init(hotkeys: [KeyCombo]) {
        self.hotkeys = hotkeys
    }

    /// A hotkey of several steps is half typed.
    public var isPending: Bool { !candidates.isEmpty }

    /// The keys to register all the time: the first step of each hotkey, once.
    public var firstChords: [KeyChord] {
        var result: [KeyChord] = []
        for chord in hotkeys.map(\.firstChord) where !result.contains(chord) { result.append(chord) }
        return result
    }

    /// While a hotkey is half typed: the keys to register for the moment. The next step of each candidate, also with any
    /// of the previous step's modifiers still held (upstream `MatchChord` accepts them), and Esc to cancel.
    public var pendingChords: [KeyChord] {
        guard isPending else { return [] }
        var result: [KeyChord] = []
        func add(_ chord: KeyChord) { if !result.contains(chord) { result.append(chord) } }
        for index in candidates {
            let steps = hotkeys[index].chords
            guard step < steps.count else { continue }
            let next = steps[step]
            let extra = steps[step - 1].modifiers & ~next.modifiers
            for held in Self.subsets(of: extra) { add(KeyChord(keyCode: next.keyCode, modifiers: next.modifiers | held)) }
        }
        add(Self.escape)
        return result
    }

    /// A registered key was pressed at `time`. `deviceFlags` (from an event tap) tell the left modifier keys from the right
    /// ones; nil (Carbon) matches either side.
    public mutating func feed(_ chord: KeyChord, deviceFlags: UInt64? = nil, at time: Date) -> Result {
        _ = expire(at: time)
        if isPending {
            if chord.keyCode == Self.escape.keyCode {
                reset()
                return .cancelled
            }
            let next = candidates.filter { index in
                let steps = hotkeys[index].chords
                return step < steps.count && Self.matches(chord, steps[step], previous: steps[step - 1], deviceFlags: deviceFlags)
            }
            if !next.isEmpty {
                candidates = next
                step += 1
                lastStepAt = time
                if let done = candidates.first(where: { hotkeys[$0].chords.count == step }) {
                    reset()
                    return .completed(done)
                }
                return .pending
            }
            // Not the next step of any candidate: start again, the key may begin another hotkey.
            reset()
        }
        if let single = hotkeys.indices.first(where: {
            hotkeys[$0].chords.count == 1 && Self.matches(chord, hotkeys[$0].firstChord, deviceFlags: deviceFlags)
        }) {
            return .completed(single)
        }
        let starts = hotkeys.indices.filter {
            hotkeys[$0].isSequence && Self.matches(chord, hotkeys[$0].firstChord, deviceFlags: deviceFlags)
        }
        guard !starts.isEmpty else { return .ignored }
        candidates = starts
        step = 1
        lastStepAt = time
        return .pending
    }

    /// Ends a half typed hotkey after `chordTimeout`; true when it did.
    public mutating func expire(at time: Date) -> Bool {
        guard isPending, let last = lastStepAt, time.timeIntervalSince(last) > Self.chordTimeout else { return false }
        reset()
        return true
    }

    public mutating func reset() {
        candidates = []
        step = 0
        lastStepAt = nil
    }

    /// The key and the modifiers of `chord`; a modifier it doesn't have may still be held from the step before. With
    /// `deviceFlags` also the sides `chord` needs.
    static func matches(_ pressed: KeyChord, _ chord: KeyChord, previous: KeyChord? = nil, deviceFlags: UInt64? = nil) -> Bool {
        guard pressed.keyCode == chord.keyCode, pressed.modifiers & chord.modifiers == chord.modifiers else { return false }
        if let deviceFlags, !chord.sidesMatch(deviceFlags: deviceFlags) { return false }
        let allowed = chord.modifiers | (previous?.modifiers ?? 0)
        return pressed.modifiers & ~allowed == 0
    }

    /// Every combination of the bits of `flags`, none first.
    static func subsets(of flags: UInt32) -> [UInt32] {
        var result: [UInt32] = [0]
        for bit in 0..<32 where flags & (1 << UInt32(bit)) != 0 {
            result += result.map { $0 | (1 << UInt32(bit)) }
        }
        return result
    }
}
