// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Binds the arguments a caller passes (CLI, `greenshot://`, browser extension, AI tool) to the arguments a trigger
/// declares (upstream `CommandlineArgumentBinder`): only declared names, required/default, type conversion. Paths go
/// through `resolvePath` (AUT's security rules and working directory); a thrown error's description is the message.
public enum RecipeArgumentBinder {
    public static func bind(declared: [CommandlineArgument], supplied: [String: String], recipeName: String,
                            resolvePath: (String, ContractDataType) throws -> String) -> Result<[String: JSONValue], RecipeStepError> {
        let arguments = declared.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        // 1. Only declared arguments are accepted, so a caller can't set internal flow variables.
        if let unknown = supplied.keys.sorted().first(where: { key in !arguments.contains { recipeEquals($0.name, key) } }) {
            let accepted = arguments.isEmpty ? "Recipe '\(recipeName)' does not accept arguments."
                                             : "Accepted arguments: \(arguments.map { "--" + $0.name }.joined(separator: ", "))."
            return .failure(usage("Error: unknown argument '\(unknown)' for recipe '\(recipeName)'. \(accepted)"))
        }
        // 2. Required, default, conversion by the declared type.
        var variables: [String: JSONValue] = [:]
        for argument in arguments {
            var raw = supplied.first { recipeEquals($0.key, argument.name) }?.value
            if raw?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
                raw = (argument.defaultValue?.isEmpty ?? true) ? nil : argument.defaultValue
            }
            guard let raw else {
                if argument.required {
                    let hint = (argument.description?.isEmpty ?? true) ? "" : " (\(argument.description!))"
                    return .failure(usage("Error: missing required argument '--\(argument.name)'\(hint)."))
                }
                continue
            }
            switch convert(argument, raw, resolvePath) {
            case .success(let value): variables[argument.effectiveVariable] = value
            case .failure(let error): return .failure(error)
            }
        }
        return .success(variables)
    }

    /// The error of a wrong command line (the CLI's usage exit code).
    private static func usage(_ message: String) -> RecipeStepError {
        RecipeStepError(message, errorType: "ArgumentException")
    }

    private static func convert(_ argument: CommandlineArgument, _ raw: String,
                                _ resolvePath: (String, ContractDataType) throws -> String) -> Result<JSONValue, RecipeStepError> {
        let name = "--" + argument.name
        var text = raw
        let allowed = argument.allowedValues ?? []
        if argument.type == .enumeration || !allowed.isEmpty {
            guard let match = allowed.first(where: { recipeEquals($0, raw) }) else {
                return .failure(usage(allowed.isEmpty ? "Error: argument '\(name)' is declared as Enum but has no allowed values."
                                                      : "Error: invalid value '\(raw)' for argument '\(name)'. Allowed values: \(allowed.joined(separator: ", "))."))
            }
            if argument.type == .enumeration || argument.type == .string { return .success(.string(match)) }
            text = match
        }
        switch argument.type {
        case .integer:
            guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else {
                return .failure(usage("Error: argument '\(name)' expects a whole number, got '\(text)'."))
            }
            return .success(.number(Double(value)))
        case .decimal:
            guard let value = Double(text.trimmingCharacters(in: .whitespaces)) else {
                return .failure(usage("Error: argument '\(name)' expects a number, got '\(text)'."))
            }
            return .success(.number(value))
        case .boolean:
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "on", "1": return .success(.bool(true))
            case "false", "no", "off", "0": return .success(.bool(false))
            default: return .failure(usage("Error: argument '\(name)' expects true or false, got '\(text)'."))
            }
        case .filePath, .directoryPath:
            do {
                return .success(.string(try resolvePath(text, argument.type)))
            } catch {
                return .failure(usage("Error: argument '\(name)': \(error.localizedDescription)"))
            }
        default:
            return .success(.string(text))
        }
    }
}
