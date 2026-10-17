// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The inside of a `${...}` as a tree. Upstream (`ExpressionEvaluator.EvaluateMathOrComparison`) splits the token list at
/// the right-most operator of the lowest precedence; this recursive descent gives the same grouping: ternary (right
/// associative) < `||` < `&&` < comparisons < `+ -` < `* / %`, each left associative, then unary minus, literals,
/// names and parentheses.
///
/// Recipe text comes from files that are checked before anyone approved them, so the parser has limits upstream
/// doesn't: at most `maxLength` UTF-8 bytes and a tree at most `maxDepth` levels deep (parentheses, unary operators,
/// ternaries and chains of binary operators all count). Deeper input is a syntax error, never a deep recursion.
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

    /// The longest expression (UTF-8 bytes) the parser reads.
    static let maxLength = 16 * 1024
    /// The deepest tree the parser builds: nesting of parentheses, unary operators and ternaries, and chains of
    /// binary operators (`a + b + c` is two levels).
    static let maxDepth = 64

    /// A node and the depth of its tree (a name or literal is 1).
    private typealias Parsed = (node: ExpressionNode, depth: Int)

    private var tokens: [Token] = []
    private var position = 0
    /// How deep the parse functions are nested right now (parentheses, unary operators, ternary branches).
    private var nesting = 0

    /// Parses the inside of a `${...}` (without the `now:` / `utcnow:` forms, which the evaluator handles first).
    static func parse(_ expression: String) throws -> ExpressionNode {
        guard expression.utf8.count <= maxLength else {
            throw ExpressionSyntaxError(message: "The expression is longer than \(maxLength / 1024) KB")
        }
        var parser = ExpressionParser()
        parser.tokens = try tokenize(expression)
        guard !parser.tokens.isEmpty else { throw ExpressionSyntaxError(message: "The expression is empty") }
        let parsed = try parser.parseTernary()
        guard parser.position == parser.tokens.count else {
            throw ExpressionSyntaxError(message: "Unexpected '\(parser.describe(parser.tokens[parser.position]))'")
        }
        return parsed.node
    }

    private static var tooDeep: ExpressionSyntaxError {
        ExpressionSyntaxError(message: "The expression is nested more than \(maxDepth) levels deep")
    }

    /// `node` with its depth, refused when the tree is too deep.
    private func checked(_ node: ExpressionNode, depth: Int) throws -> Parsed {
        guard depth <= Self.maxDepth else { throw Self.tooDeep }
        return (node, depth)
    }

    /// Runs `body` one nesting level deeper; refuses before the recursion gets deep.
    private mutating func nested(_ body: (inout ExpressionParser) throws -> Parsed) throws -> Parsed {
        nesting += 1
        defer { nesting -= 1 }
        guard nesting <= Self.maxDepth else { throw Self.tooDeep }
        return try body(&self)
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

    private static let pairSymbols: Set<String> = ["==", "!=", "<=", ">=", "&&", "||"]
    private static let singleSymbols: Set<Character> = ["<", ">", "+", "-", "*", "/", "%", "?", ":", "(", ")"]

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
            // Only the next two characters are looked at: copying the rest for each symbol is quadratic.
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "?", next == "?" {
                throw ExpressionSyntaxError(message: "'??' is not supported")
            }
            if let next, pairSymbols.contains(String([character, next])) {
                tokens.append(.symbol(String([character, next])))
                index += 2
                continue
            }
            guard singleSymbols.contains(character) else {
                throw ExpressionSyntaxError(message: "'\(character)' can't be used here")
            }
            tokens.append(.symbol(String(character)))
            index += 1
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

    private mutating func parseTernary() throws -> Parsed {
        let condition = try parseBinary(level: 0)
        guard peekSymbol() == "?" else { return condition }
        position += 1
        let whenTrue = try nested { try $0.parseTernary() }
        try expect(":")
        let whenFalse = try nested { try $0.parseTernary() }
        let depth = max(condition.depth, whenTrue.depth, whenFalse.depth) + 1
        return try checked(.ternary(condition.node, whenTrue.node, whenFalse.node), depth: depth)
    }

    private static let levels: [[String]] = [["||"], ["&&"], ["==", "!=", "<=", ">=", "<", ">"], ["+", "-"], ["*", "/", "%"]]

    private mutating func parseBinary(level: Int) throws -> Parsed {
        guard level < Self.levels.count else { return try parseUnary() }
        var parsed = try parseBinary(level: level + 1)
        while let symbol = peekSymbol(), Self.levels[level].contains(symbol) {
            position += 1
            let right = try parseBinary(level: level + 1)
            parsed = try checked(.binary(symbol, parsed.node, right.node), depth: max(parsed.depth, right.depth) + 1)
        }
        return parsed
    }

    private mutating func parseUnary() throws -> Parsed {
        if peekSymbol() == "-" {
            position += 1
            let operand = try nested { try $0.parseUnary() }
            return try checked(.negate(operand.node), depth: operand.depth + 1)
        }
        if peekSymbol() == "+" {
            position += 1
            return try nested { try $0.parseUnary() }
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> Parsed {
        guard position < tokens.count else { throw ExpressionSyntaxError(message: "The expression ends too early") }
        let token = tokens[position]
        position += 1
        switch token {
        case .number(let number):
            return (.literal(.number(number)), 1)
        case .text(let text):
            return (.literal(.string(text)), 1)
        case .name(let name):
            return (.name(name), 1)
        case .symbol("("):
            let inner = try nested { try $0.parseTernary() }
            try expect(")")
            return inner
        case .symbol(let symbol):
            throw ExpressionSyntaxError(message: "Unexpected '\(symbol)'")
        }
    }
}
