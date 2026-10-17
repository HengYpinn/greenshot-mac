// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import SwiftUI

/// The Flow tab: the recipe's flow drawn natively from the same graph as the Mermaid text (upstream's "Mermaid" toggle,
/// RecipeEditorWindow.xaml:968-980, shows the text), the text itself and "Copy Mermaid Code". Clicking a step selects it.
struct RecipeFlowTab: View {
    @ObservedObject var model: RecipeEditorModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                if let recipe = model.recipe {
                    RecipeFlowDiagram(graph: RecipeFlowGraph(recipe), selectedNode: model.selectedNode?.id) { model.select(nodeId: $0) }
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Mermaid").font(.headline)
                    Text("Paste it into Markdown, GitHub READMEs or pull requests.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Mermaid Code") { model.copyMermaid() }
                }
                ScrollView {
                    Text(RecipeMermaid.text(of: model.recipe))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .frame(height: 200)
        }
    }
}

/// A `RecipeFlowGraph` laid out by `RecipeFlowLayout`.
struct RecipeFlowDiagram: View {
    let graph: RecipeFlowGraph
    var selectedNode: String?
    var select: (String) -> Void

    private static let font = NSFont.systemFont(ofSize: 11)

    static func size(of node: RecipeFlowGraph.Node) -> CGSize {
        let text = (node.label as NSString).size(withAttributes: [.font: font])
        let width = min(max(text.width + 26, 110), 250)
        switch node.shape {
        case .diamond: return CGSize(width: width + 40, height: 56)
        case .stadium: return CGSize(width: width, height: 30)
        case .box: return CGSize(width: width, height: 34)
        }
    }

    var body: some View {
        let layout = RecipeFlowLayout(graph, size: Self.size(of:))
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in graph.edges { draw(edge, layout: layout, in: &context) }
            }
            ForEach(graph.edges.indices, id: \.self) { index in
                edgeLabel(graph.edges[index], layout: layout)
            }
            ForEach(graph.nodes) { node in
                if let frame = layout.frames[node.id] {
                    RecipeFlowNodeView(node: node, isSelected: node.nodeId != nil && node.nodeId == selectedNode)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .onTapGesture { if let id = node.nodeId { select(id) } }
                        .help(node.label)
                }
            }
        }
        .frame(width: max(layout.size.width, 200), height: max(layout.size.height, 120), alignment: .topLeading)
    }

    private func color(_ style: RecipeFlowGraph.EdgeStyle) -> Color {
        switch style {
        case .normal: return .secondary
        case .conditional: return .accentColor
        case .error: return .red
        case .trigger: return .orange
        }
    }

    private func draw(_ edge: RecipeFlowGraph.Edge, layout: RecipeFlowLayout, in context: inout GraphicsContext) {
        let points = layout.path(of: edge)
        guard points.count >= 2 else { return }
        var path = Path()
        path.addLines(points)
        let dash: [CGFloat] = edge.style == .error ? [6, 4] : edge.style == .trigger ? [2, 3] : []
        context.stroke(path, with: .color(color(edge.style)), style: StrokeStyle(lineWidth: 1.4, dash: dash))
        // Arrow head along the last segment.
        let end = points[points.count - 1]
        let before = points[points.count - 2]
        let angle = atan2(Double(end.y - before.y), Double(end.x - before.x))
        let length = 8.0
        let spread = 0.45
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: Double(end.x) - length * cos(angle - spread), y: Double(end.y) - length * sin(angle - spread)))
        head.addLine(to: CGPoint(x: Double(end.x) - length * cos(angle + spread), y: Double(end.y) - length * sin(angle + spread)))
        head.closeSubpath()
        context.fill(head, with: .color(color(edge.style)))
    }

    @ViewBuilder private func edgeLabel(_ edge: RecipeFlowGraph.Edge, layout: RecipeFlowLayout) -> some View {
        let points = layout.path(of: edge)
        if let label = edge.label, points.count >= 3 {
            // On the last segment, so the labels of a decision's branches don't cover each other.
            let a = points[points.count - 2]
            let b = points[points.count - 1]
            Text(label)
                .font(.system(size: 10))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
                .foregroundStyle(color(edge.style))
                .fixedSize()
                .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
    }
}

/// One node: a rounded box (step), a diamond (Conditional) or a stadium (trigger, "Any step", Out); start steps green
/// and triggers amber like upstream's Mermaid classDefs.
private struct RecipeFlowNodeView: View {
    let node: RecipeFlowGraph.Node
    let isSelected: Bool

    var body: some View {
        let fill = fillColor
        let text = node.isStart || node.role == .trigger ? Color.white : Color.primary
        ZStack {
            shape.fill(fill)
            shape.stroke(strokeColor, style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1, dash: dashed ? [4, 3] : []))
            Text(node.label)
                .font(.system(size: 11))
                .foregroundStyle(node.isDisabled ? Color.secondary : text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, node.shape == .diamond ? 26 : 8)
        }
    }

    private var shape: AnyShape {
        switch node.shape {
        case .box: return AnyShape(RoundedRectangle(cornerRadius: 6))
        case .stadium: return AnyShape(Capsule())
        case .diamond: return AnyShape(RecipeDiamond())
        }
    }

    private var dashed: Bool { node.isDisabled || node.role == .missing || node.role == .recipe || node.role == .anyStep }

    private var fillColor: Color {
        if node.role == .trigger { return Color(red: 0xd9 / 255, green: 0x77 / 255, blue: 0x06 / 255) }
        if node.isStart { return Color(red: 0x23 / 255, green: 0x86 / 255, blue: 0x36 / 255) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var strokeColor: Color {
        if isSelected { return .accentColor }
        if node.role == .missing { return .red }
        if node.role == .trigger { return Color(red: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255) }
        if node.isStart { return Color(red: 0x2e / 255, green: 0xa0 / 255, blue: 0x43 / 255) }
        return .secondary
    }
}

private struct RecipeDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
