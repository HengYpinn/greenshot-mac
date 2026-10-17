// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where `user.*`, `machine.*`, `config.*` and the clock come from. Tests pass fixed values; the app passes
/// `SystemRecipeEnvironment` with a snapshot of the settings.
public protocol RecipeEnvironment: Sendable {
    /// `user.username`, `user.desktop`, ... (upstream `ResolveUserEnvironment`, macOS folders), then the environment.
    func userValue(_ key: String) -> JSONValue?
    /// `machine.computername`, `machine.os`, ... (upstream `ResolveMachineEnvironment`; Windows-only names are empty).
    func machineValue(_ key: String) -> JSONValue?
    /// `config.<name>`: a setting by its upstream `greenshot.ini` name or its Mac name, case-insensitive; read-only.
    func configValue(_ key: String) -> JSONValue?
    func now() -> Date
    var timeZone: TimeZone { get }
}

/// The real environment: NSUserName, the user's folders, ProcessInfo, and `config.*` from the settings snapshot through
/// a table of upstream names (`language`, `capturemousepointer`, `outputfilepath`, ...).
public struct SystemRecipeEnvironment: RecipeEnvironment {
    public init(settings: AppSettings) { rcoreStub() }
    public func userValue(_ key: String) -> JSONValue? { rcoreStub() }
    public func machineValue(_ key: String) -> JSONValue? { rcoreStub() }
    public func configValue(_ key: String) -> JSONValue? { rcoreStub() }
    public func now() -> Date { Date() }
    public var timeZone: TimeZone { .current }
}
