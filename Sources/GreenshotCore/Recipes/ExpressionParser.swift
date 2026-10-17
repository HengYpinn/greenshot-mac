// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The inside of a `${...}` as a tree. Upstream (`ExpressionEvaluator.EvaluateMathOrComparison`) splits the token list at
/// the right-most operator of the lowest precedence; this recursive descent gives the same grouping: ternary (right
/// associative) < `||` < `&&` < comparisons < `+ -` < `* / %`, each left associative, then unary minus, literals,
/// names and parentheses.
indirect enum ExpressionNode: Equatable {
    case literal(JSONValue)
    case name(String)
    case negate(ExpressionNode)
    case binary(String, ExpressionNode, ExpressionNode)
    case ternary(ExpressionNode, ExpressionNode, ExpressionNode)
}

struct ExpressionSyntaxError: Error, Equatable {
    let message: String
}

struct ExpressionParser {
    private enum Token: Equatable {
        case number(Double)
        case text(String)
        case name(String)
        case symbol(String)
    }

    private var tokens: [Token] = []
    private var position = 0

    /// Parses the inside of a `${...}` (without the `now:` / `utcnow:` forms, which the evaluator handles first).
    static func parse(_ expression: String) throws -> ExpressionNode {
        var parser = ExpressionParser()
        parser.tokens = try tokenize(expression)
        guard !parser.tokens.isEmpty else { throw ExpressionSyntaxError(message: "The expression is empty") }
        let node = try parser.parseTernary()
        guard parser.position == parser.tokens.count else {
            throw ExpressionSyntaxError(message: "Unexpected '\(parser.describe(parser.tokens[parser.position]))'")
        }
        return node
    }

    private func describe(_ token: Token) -> String {
        switch token {
        case .number(let number): return JSONValue.format(number)
        case .text(let text): return "'\(text)'"
        case .name(let name): return name
        case .symbol(let symbol): return symbol
        }
    }

    // MARK: Tokens

    private static let symbols = ["==", "!=", "<=", ">=", "&&", "||", "<", ">", "+", "-", "*", "/", "%", "?", ":", "(", ")"]

    private static func tokenize(_ text: String) throws -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0
        func isNameStart(_ character: Character) -> Bool { character.isLetter || character == "_" || character == "$" }
        func isNamePart(_ character: Character) -> Bool { isNameStart(character) || character.isNumber || character == "." }
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character == "'" || character == "\"" {
                guard let end = characters[(index + 1)...].firstIndex(of: character) else {
                    throw ExpressionSyntaxError(message: "A text in quotes is not closed")
                }
                tokens.append(.text(String(characters[(index + 1)..<end])))
                index = end + 1
                continue
            }
            if character.isNumber || (character == "." && index + 1 < characters.count && characters[index + 1].isNumber) {
                var end = index
                while end < characters.count, characters[end].isNumber || characters[end] == "." { end += 1 }
                if end < characters.count, characters[end] == "e" || characters[end] == "E" {
                    var exponent = end + 1
                    if exponent < characters.count, characters[exponent] == "+" || characters[exponent] == "-" { exponent += 1 }
                    if exponent < characters.count, characters[exponent].isNumber {
                        end = exponent
                        while end < characters.count, characters[end].isNumber { end += 1 }
                    }
                }
                let literal = String(characters[index..<end])
                guard let number = Double(literal) else { throw ExpressionSyntaxError(message: "'\(literal)' is not a number") }
                if end < characters.count, isNameStart(characters[end]) {
                    throw ExpressionSyntaxError(message: "'\(literal)\(characters[end])' is not a number or a name")
                }
                tokens.append(.number(number))
                index = end
                continue
            }
            if isNameStart(character) {
                var end = index
                while end < characters.count, isNamePart(characters[end]) { end += 1 }
                tokens.append(.name(String(characters[index..<end])))
                index = end
                continue
            }
            let rest = String(characters[index...])
            guard let symbol = symbols.first(where: { rest.hasPrefix($0) }) else {
                throw ExpressionSyntaxError(message: "'\(character)' can't be used here")
            }
            if symbol == "?", rest.hasPrefix("??") {
                throw ExpressionSyntaxError(message: "'??' is not supported")
            }
            tokens.append(.symbol(symbol))
            index += symbol.count
        }
        return tokens
    }

    // MARK: Grammar

    private func peekSymbol() -> String? {
        guard position < tokens.count, case .symbol(let symbol) = tokens[position] else { return nil }
        return symbol
    }

    private mutating func expect(_ symbol: String) throws {
        guard peekSymbol() == symbol else {
            throw ExpressionSyntaxError(message: position < tokens.count ? "Expected '\(symbol)' instead of '\(describe(tokens[position]))'"
                                                                       : "Expected '\(symbol)' at the end")
        }
        position += 1
    }

    private mutating func parseTernary() throws -> ExpressionNode {
        let condition = try parseBinary(level: 0)
        guard peekSymbol() == "?" else { return condition }
        position += 1
        let whenTrue = try parseTernary()
        try expect(":")
        let whenFalse = try parseTernary()
        return .ternary(condition, whenTrue, whenFalse)
    }

    private static let levels: [[String]] = [["||"], ["&&"], ["==", "!=", "<=", ">=", "<", ">"], ["+", "-"], ["*", "/", "%"]]

    private mutating func parseBinary(level: Int) throws -> ExpressionNode {
        guard level < Self.levels.count else { return try parseUnary() }
        var node = try parseBinary(level: level + 1)
        while let symbol = peekSymbol(), Self.levels[level].contains(symbol) {
            position += 1
            let right = try parseBinary(level: level + 1)
            node = .binary(symbol, node, right)
        }
        return node
    }

    private mutating func parseUnary() throws -> ExpressionNode {
        if peekSymbol() == "-" {
            position += 1
            return .negate(try parseUnary())
        }
        if peekSymbol() == "+" {
            position += 1
            return try parseUnary()
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> ExpressionNode {
        guard position < tokens.count else { throw ExpressionSyntaxError(message: "The expression ends too early") }
        let token = tokens[position]
        position += 1
        switch token {
        case .number(let number):
            return .literal(.number(number))
        case .text(let text):
            return .literal(.string(text))
        case .name(let name):
            return .name(name)
        case .symbol("("):
            let inner = try parseTernary()
            try expect(")")
            return inner
        case .symbol(let symbol):
            throw ExpressionSyntaxError(message: "Unexpected '\(symbol)'")
        }
    }
}
