// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// What a step needs from and does to the image (upstream `PayloadRequirement`).
public enum PayloadRequirement: String, Sendable, Codable, CaseIterable {
    case none, required, optional, created
}

/// How a step changes the image (upstream `PayloadEffect`).
public enum PayloadEffect: String, Sendable, Codable, CaseIterable {
    case none, mutatesPixels, addsAnnotations, replacesImage
}

/// The kinds of actions that need the user's permission (upstream `RecipeGateType`).
public enum RecipeGateType: String, Sendable, Codable, CaseIterable, Comparable {
    case externalCommand = "ExternalCommand"
    case networkAccess = "NetworkAccess"
    case fileSystemAccess = "FileSystemAccess"
    case custom = "Custom"

    public static func < (lhs: RecipeGateType, rhs: RecipeGateType) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// For messages: "external commands", "network access (uploads)", "file system access", "custom actions"
    /// (upstream `RecipeApprovalPolicy.GetGateName`).
    public var displayName: String {
        switch self {
        case .externalCommand: return "external commands"
        case .networkAccess: return "network access (uploads)"
        case .fileSystemAccess: return "file system access"
        case .custom: return "custom actions"
        }
    }
}

/// A gated action of a step (upstream `RecipeGatedAction`): equal when the type and the target (case-insensitive) are.
public struct RecipeGatedAction: Sendable, Hashable {
    public var gateType: RecipeGateType
    /// What it acts on: "Jira", "Writes files to ~/Shots", the command line.
    public var target: String

    public init(_ gateType: RecipeGateType, target: String) {
        self.gateType = gateType
        self.target = target
    }

    public static func == (lhs: RecipeGatedAction, rhs: RecipeGatedAction) -> Bool {
        lhs.gateType == rhs.gateType && lhs.target.caseInsensitiveCompare(rhs.target) == .orderedSame
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(gateType)
        hasher.combine(target.lowercased())
    }
}

/// A parameter of a step or trigger (upstream `ParameterContract`). Names are case-insensitive.
public struct ParameterContract: Sendable {
    public var name: String
    public var dataType: ContractDataType
    public var required: Bool
    public var defaultValue: JSONValue?
    public var description: String
    /// Allowed values (case-insensitive), empty for any. `allowedValuesProvider` wins when set (upstream
    /// `IAllowedValuesProvider`, e.g. the file formats).
    public var allowedValues: [String]
    public var allowedValuesProvider: (@Sendable () -> [String])?
    /// False: the value is used as written, `${...}` is not evaluated (e.g. Source `SourceType`, Conditional `Branches`).
    public var supportsExpressions: Bool

    public init(_ name: String, _ dataType: ContractDataType = .string, required: Bool = false, defaultValue: JSONValue? = nil,
                description: String = "", allowedValues: [String] = [], supportsExpressions: Bool = true) {
        self.name = name
        self.dataType = dataType
        self.required = required
        self.defaultValue = defaultValue
        self.description = description
        self.allowedValues = allowedValues
        self.supportsExpressions = supportsExpressions
    }

    public var effectiveAllowedValues: [String] { allowedValuesProvider?() ?? allowedValues }
    public func matches(_ parameterName: String) -> Bool { name.caseInsensitiveCompare(parameterName) == .orderedSame }
}

/// An input or output variable of a step (upstream `VariableContract`). A name can depend on the node: `{NodeId}`,
/// `{Parameter:X}` (the value of parameter X), or a whole name `{ParameterKeys:X}` (every key of the object X).
public struct VariableContract: Sendable, Equatable {
    public var name: String
    public var dataType: ContractDataType
    public var required: Bool
    public var description: String
    public var exampleValue: String?
    /// Outputs: not always set (e.g. only when a barcode was found).
    public var conditional: Bool
    /// Outputs: a conditional output that is always set when the node has this parameter.
    public var whenParameter: String?

    public init(_ name: String, _ dataType: ContractDataType = .string, required: Bool = false, description: String = "",
                exampleValue: String? = nil, conditional: Bool = false, whenParameter: String? = nil) {
        self.name = name
        self.dataType = dataType
        self.required = required
        self.description = description
        self.exampleValue = exampleValue
        self.conditional = conditional
        self.whenParameter = whenParameter
    }

    public var isNodeSpecific: Bool { name.contains("{") }
    /// The variable name(s) for the node, placeholders replaced; empty when a parameter placeholder isn't set.
    public func resolveNames(for node: RecipeNode) -> [String] {
        guard !name.isEmpty else { return [] }
        guard name.contains("{") else { return [name] }
        var result = name.replacingOccurrences(of: "{NodeId}", with: node.id)
        let keysPrefix = "{ParameterKeys:"
        if result.hasPrefix(keysPrefix), result.hasSuffix("}") {
            let parameter = String(result.dropFirst(keysPrefix.count).dropLast())
            let keys = node.parameters[parameter]?.objectValue?.keys ?? []
            return keys.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        let parameterPrefix = "{Parameter:"
        while let start = result.range(of: parameterPrefix) {
            guard let end = result.range(of: "}", range: start.upperBound..<result.endIndex) else { return [] }
            let parameter = String(result[start.upperBound..<end.lowerBound])
            guard let value = node.parameters[parameter]?.asString, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
            result.replaceSubrange(start.lowerBound..<end.upperBound, with: value)
        }
        return [result]
    }
    /// Always set by this node: not conditional, or its `whenParameter` is set.
    public func isGuaranteed(for node: RecipeNode) -> Bool {
        guard conditional else { return true }
        guard let whenParameter, let value = node.parameters[whenParameter], !value.isNull else { return false }
        if let text = value.stringValue { return !text.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }
}

/// What a step needs and does to the image (upstream `PayloadContract`).
public struct PayloadContract: Sendable, Equatable {
    public var rawCapture: PayloadRequirement
    public var surface: PayloadRequirement
    public var extractedText: PayloadRequirement
    public var visualMutation: PayloadEffect

    public init(rawCapture: PayloadRequirement = .none, surface: PayloadRequirement = .none,
                extractedText: PayloadRequirement = .none, visualMutation: PayloadEffect = .none) {
        self.rawCapture = rawCapture
        self.surface = surface
        self.extractedText = extractedText
        self.visualMutation = visualMutation
    }
}

/// What the gate check of a step may look up besides the node: the external commands of the settings (the command line
/// of a named command) and the destinations of the settings (a Destinations node without designations exports to
/// them, upstream `ResolveDestinationDesignations` priority 4).
public struct GateEnvironment: Sendable {
    public var commandLine: @Sendable (String) -> String?
    public var defaultDestinations: [String]

    public init(commandLine: @escaping @Sendable (String) -> String? = { _ in nil }, defaultDestinations: [String] = []) {
        self.commandLine = commandLine
        self.defaultDestinations = defaultDestinations
    }

    public static let empty = GateEnvironment()
    /// From the settings: `externalCommands` and `destinations`.
    public init(settings: AppSettings) {
        let commands = settings.externalCommands
        self.commandLine = { name in
            commands.first { recipeEquals($0.name, name) }?.command
        }
        self.defaultDestinations = settings.destinations.map(RecipeDestinationDesignation.designation(for:))
    }
}

/// The contract of a step type (upstream `StepContract`, built from the `[Step*]` attributes): its parameters, the
/// variables it reads and sets, what it does to the image, and which gated actions a node of it does (upstream
/// `IRequiresRecipeAuthorization.GetGatedActions`, here a pure function of the node so validation, the describer and
/// `--info` work without the app).
public struct StepContract: Sendable {
    public var stepType: String
    public var displayName: String
    public var description: String
    public var category: String
    public var parameters: [ParameterContract]
    public var inputVariables: [VariableContract]
    public var outputVariables: [VariableContract]
    public var payload: PayloadContract
    /// The step reads more parameters than declared (Annotation): undeclared ones aren't reported.
    public var acceptsUndeclaredParameters: Bool
    /// The step evaluates the `${...}` in its parameters itself and gets them raw (upstream `IEvaluatesOwnParameters`).
    public var evaluatesOwnParameters: Bool
    public var gates: @Sendable (RecipeNode, GateEnvironment) -> [RecipeGatedAction]

    public init(stepType: String, displayName: String, description: String = "", category: String = "General",
                parameters: [ParameterContract] = [], inputVariables: [VariableContract] = [],
                outputVariables: [VariableContract] = [], payload: PayloadContract = PayloadContract(),
                acceptsUndeclaredParameters: Bool = false, evaluatesOwnParameters: Bool = false,
                gates: @escaping @Sendable (RecipeNode, GateEnvironment) -> [RecipeGatedAction] = { _, _ in [] }) {
        self.stepType = stepType
        self.displayName = displayName
        self.description = description
        self.category = category
        self.parameters = parameters
        self.inputVariables = inputVariables
        self.outputVariables = outputVariables
        self.payload = payload
        self.acceptsUndeclaredParameters = acceptsUndeclaredParameters
        self.evaluatesOwnParameters = evaluatesOwnParameters
        self.gates = gates
    }

    public func parameter(_ name: String) -> ParameterContract? { parameters.first { $0.matches(name) } }
}

/// The contracts of the step types by step type (case-insensitive; upstream `StepRegistry` contracts). `builtIn` has
/// every step type of upstream, the plug-in steps included (ExternalCommand, Jira, Confluence, Box, Dropbox, Office,
/// Pdf, BarcodeScan), whether or not the app has an executor for it yet.
public struct StepContractCatalog: Sendable {
    public static var builtIn: StepContractCatalog { builtInCatalog }
    private static let builtInCatalog = StepContractCatalog(BuiltInStepContracts.all)

    private var contracts: [StepContract]
    private var byType: [String: Int]

    public init(_ contracts: [StepContract]) {
        self.contracts = []
        self.byType = [:]
        for contract in contracts {
            insert(contract)
        }
    }

    private mutating func insert(_ contract: StepContract) {
        let key = contract.stepType.lowercased()
        if let index = byType[key] {
            contracts[index] = contract
        } else {
            byType[key] = contracts.count
            contracts.append(contract)
        }
    }

    public var all: [StepContract] { contracts }
    public func contract(for stepType: String) -> StepContract? { byType[stepType.lowercased()].map { contracts[$0] } }
    public func contains(_ stepType: String) -> Bool { contract(for: stepType) != nil }
    /// A copy with the contract added or replaced.
    public func adding(_ contract: StepContract) -> StepContractCatalog {
        var copy = self
        copy.insert(contract)
        return copy
    }
}
