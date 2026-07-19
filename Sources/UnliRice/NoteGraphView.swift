import SwiftUI
import UnliRiceCore

struct GraphNode: Identifiable, Equatable {
    let id: UUID
    let title: String
    let tags: Set<String>
    var x: Double
    var y: Double
    var vx: Double = 0
    var vy: Double = 0
    var color: Color
    var primaryTag: String?
    
    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.id == rhs.id && lhs.x == rhs.x && lhs.y == rhs.y
    }
}

struct GraphEdge: Identifiable, Equatable {
    let id: String
    let source: UUID
    let target: UUID
}

struct NoteGraphView: View {
    @EnvironmentObject var store: AppStore
    
    // Physics & nodes state
    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []
    @State private var alpha: Double = 1.0  // temperature for physics simulation
    
    // UI state
    @State private var zoom: Double = 1.0
    @State private var pan: CGSize = .zero
    @State private var accumulatedPan: CGSize = .zero
    @State private var hoveredNodeID: UUID? = nil
    @State private var selectedNodeID: UUID? = nil
    @State private var draggedNodeID: UUID? = nil
    @State private var filterTag: String? = nil
    
    // Physics constants
    private let charge: Double = -450.0       // repulsion force
    private let springStrength: Double = 0.05  // link attraction force
    private let restLength: Double = 130.0     // desired link length
    private let centerGravity: Double = 0.01   // pull to (0,0)
    private let clusterGravity: Double = 0.04  // pull to cluster centers
    private let friction: Double = 0.88
    
    // Timer for physics ticks (runs at 60fps when alpha is high)
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid pattern
                backgroundGrid
                
                // Main graph canvas
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    
                    // Apply zoom & pan translation
                    context.translateBy(x: center.x + pan.width, y: center.y + pan.height)
                    context.scaleBy(x: zoom, y: zoom)
                    
                    // Draw edges (lines)
                    drawEdges(in: context)
                    
                    // Draw nodes
                    drawNodes(in: context)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            
                            // 1. Identify node under touch at start of drag
                            if draggedNodeID == nil {
                                let startCanvasX = (value.startLocation.x - center.x - accumulatedPan.width) / zoom
                                let startCanvasY = (value.startLocation.y - center.y - accumulatedPan.height) / zoom
                                if let node = findNode(at: CGPoint(x: startCanvasX, y: startCanvasY)) {
                                    draggedNodeID = node.id
                                    selectedNodeID = node.id
                                }
                            }
                            
                            // 2. Perform drag operation
                            if let nodeID = draggedNodeID {
                                // Dragging a node
                                if let idx = nodes.firstIndex(where: { $0.id == nodeID }) {
                                    let canvasX = (value.location.x - center.x - accumulatedPan.width) / zoom
                                    let canvasY = (value.location.y - center.y - accumulatedPan.height) / zoom
                                    nodes[idx].x = canvasX
                                    nodes[idx].y = canvasY
                                    nodes[idx].vx = 0
                                    nodes[idx].vy = 0
                                    alpha = 1.0  // Re-heat simulation
                                }
                            } else {
                                // Panning the background
                                pan = CGSize(
                                    width: accumulatedPan.width + value.translation.width,
                                    height: accumulatedPan.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { value in
                            if draggedNodeID == nil {
                                accumulatedPan = pan
                            } else {
                                draggedNodeID = nil
                            }
                        }
                )
                // Pinch-to-zoom support (combines zoom gestures)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = max(0.15, min(4.0, value))
                            alpha = 0.5  // Gentle re-heat to adjust labels
                        }
                )
                .onContinuousHover { phase in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    switch phase {
                    case .active(let location):
                        let canvasX = (location.x - center.x - pan.width) / zoom
                        let canvasY = (location.y - center.y - pan.height) / zoom
                        if let node = findNode(at: CGPoint(x: canvasX, y: canvasY)) {
                            hoveredNodeID = node.id
                        } else {
                            hoveredNodeID = nil
                        }
                    case .ended:
                        hoveredNodeID = nil
                    }
                }
                
                // UI Overlay: Legend and Inspector
                VStack {
                    HStack {
                        tagLegend
                        Spacer()
                        controlsPanel
                    }
                    .padding(16)
                    
                    Spacer()
                    
                    if let selectedNode = nodes.first(where: { $0.id == selectedNodeID }) {
                        inspectorPanel(for: selectedNode)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .background(Theme.background)
        .onAppear(perform: initializeGraph)
        .onReceive(timer) { _ in
            tickPhysics()
        }
    }
    
    // MARK: - Canvas Rendering
    
    private func drawEdges(in context: GraphicsContext) {
        for edge in edges {
            guard let sourceNode = nodes.first(where: { $0.id == edge.source }),
                  let targetNode = nodes.first(where: { $0.id == edge.target }) else { continue }
            
            // Check filters
            let isFiltered = filterTag != nil && 
                             !sourceNode.tags.contains(filterTag!) && 
                             !targetNode.tags.contains(filterTag!)
            
            var path = Path()
            path.move(to: CGPoint(x: sourceNode.x, y: sourceNode.y))
            path.addLine(to: CGPoint(x: targetNode.x, y: targetNode.y))
            
            if isFiltered {
                context.stroke(path, with: .color(Color.gray.opacity(0.04)), lineWidth: 0.5)
            } else {
                let edgeColor = sourceNode.color
                // 1. Glowing background stroke
                context.stroke(path, with: .color(edgeColor.opacity(0.08)), lineWidth: 3.5)
                // 2. Sharp core stroke
                context.stroke(path, with: .color(edgeColor.opacity(0.28)), lineWidth: 1.25)
            }
        }
    }
    
    private func drawNodes(in context: GraphicsContext) {
        for node in nodes {
            let radius = 12.0
            let isHovered = hoveredNodeID == node.id
            let isSelected = selectedNodeID == node.id
            let isFiltered = filterTag != nil && !node.tags.contains(filterTag!)
            
            let baseColor = node.color
            let opacity = isFiltered ? 0.12 : (isHovered || isSelected ? 0.95 : 0.75)
            
            // 1. Glowing outer blur layer (liquid glass glow)
            if !isFiltered {
                let glowRadius = radius * (isHovered || isSelected ? 3.5 : 2.2)
                let glowRect = CGRect(x: node.x - glowRadius, y: node.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                let shading = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [baseColor.opacity(0.4), baseColor.opacity(0.05), .clear]),
                    center: CGPoint(x: node.x, y: node.y),
                    startRadius: 0,
                    endRadius: glowRadius
                )
                context.fill(Path(ellipseIn: glowRect), with: shading)
            }
            
            // 2. Base node body circle (translucent glass core)
            let nodeRect = CGRect(x: node.x - radius, y: node.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: nodeRect), with: .color(baseColor.opacity(isFiltered ? 0.15 : 0.6)))
            
            // 3. Specular Highlight (The 3D Liquid Glass Effect!)
            if !isFiltered {
                let highlightCenter = CGPoint(x: node.x - radius * 0.35, y: node.y - radius * 0.35)
                let highlightShading = GraphicsContext.Shading.radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.55),
                        baseColor.opacity(0.1),
                        Color.clear
                    ]),
                    center: highlightCenter,
                    startRadius: 0,
                    endRadius: radius * 1.3
                )
                context.fill(Path(ellipseIn: nodeRect), with: highlightShading)
            }
            
            // 4. Frosted Outer Glass Rim Stroke
            let strokeColor = isSelected ? Color.white : (isHovered ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
            context.stroke(Path(ellipseIn: nodeRect), with: .color(strokeColor), lineWidth: isSelected ? 1.75 : 1.0)
            
            // 5. Draw Labels with transparent black capsule backing
            if zoom > 0.65 || isHovered || isSelected {
                if !isFiltered || isSelected {
                    let labelText = Text(node.title)
                        .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium, design: .monospaced))
                        .foregroundColor(isSelected ? Theme.ink : Theme.inkDim)
                    
                    let resolved = context.resolve(labelText)
                    let textSize = resolved.measure(in: CGSize(width: 300, height: 100))
                    
                    // Draw a beautiful dark glass-like capsule background behind the text to ensure legibility
                    let bgRect = CGRect(
                        x: node.x - textSize.width / 2.0 - 5.0,
                        y: node.y + radius + 4.0,
                        width: textSize.width + 10.0,
                        height: textSize.height + 4.0
                    )
                    context.fill(
                        Path(roundedRect: bgRect, cornerRadius: 4.0),
                        with: .color(Color.black.opacity(0.65))
                    )
                    context.stroke(
                        Path(roundedRect: bgRect, cornerRadius: 4.0),
                        with: .color(Color.white.opacity(0.08)),
                        lineWidth: 0.5
                    )
                    
                    context.draw(resolved, at: CGPoint(x: node.x, y: node.y + radius + 6), anchor: .top)
                }
            }
        }
    }
    
    // MARK: - Physics Simulation Ticks
    
    private func tickPhysics() {
        guard alpha > 0.005 else { return }
        
        let nodeCount = nodes.count
        guard nodeCount > 0 else { return }
        
        // 1. Repulsion (Charge) - O(N log N) simplified via dynamic stepping for large N
        let step = max(1, nodeCount / 80) // Prevents lag at 5k notes, limits checks to ~80 per node
        for i in 0..<nodeCount {
            for j in stride(from: i + 1, to: nodeCount, by: step) {
                let dx = nodes[i].x - nodes[j].x
                let dy = nodes[i].y - nodes[j].y
                let distSq = dx*dx + dy*dy + 0.1
                
                // Repel notes if they are within range
                if distSq < 160000 { // 400px range
                    let dist = sqrt(distSq)
                    let force = charge / distSq
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force
                    
                    nodes[i].vx += fx
                    nodes[i].vy += fy
                    nodes[j].vx -= fx
                    nodes[j].vy -= fy
                }
            }
        }
        
        // 2. Attraction (Edges / Links)
        for edge in edges {
            guard let sourceIdx = nodes.firstIndex(where: { $0.id == edge.source }),
                  let targetIdx = nodes.firstIndex(where: { $0.id == edge.target }) else { continue }
            
            let dx = nodes[targetIdx].x - nodes[sourceIdx].x
            let dy = nodes[targetIdx].y - nodes[sourceIdx].y
            let distSq = dx*dx + dy*dy + 0.1
            let dist = sqrt(distSq)
            
            let force = (dist - restLength) * springStrength
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force
            
            nodes[sourceIdx].vx += fx
            nodes[sourceIdx].vy += fy
            nodes[targetIdx].vx -= fx
            nodes[targetIdx].vy -= fy
        }
        
        // 3. Gravity (Center pull + Clustered tag pull)
        for i in 0..<nodeCount {
            let node = nodes[i]
            
            // Core gravity pull to center (0,0)
            nodes[i].vx -= node.x * centerGravity
            nodes[i].vy -= node.y * centerGravity
            
            // Cluster centers depending on primary tag
            if let tag = node.primaryTag {
                let targetCenter: CGPoint
                switch tag {
                case "ai-context":
                    targetCenter = CGPoint(x: 0, y: -160)
                case "guardrails":
                    targetCenter = CGPoint(x: -160, y: 50)
                case "projects":
                    targetCenter = CGPoint(x: 160, y: 50)
                case "system":
                    targetCenter = CGPoint(x: 0, y: 160)
                default:
                    targetCenter = .zero
                }
                
                nodes[i].vx += (targetCenter.x - node.x) * clusterGravity
                nodes[i].vy += (targetCenter.y - node.y) * clusterGravity
            }
        }
        
        // 4. Update coordinates & apply cooling
        for i in 0..<nodeCount {
            // Keep dragged node pinned under cursor
            if nodes[i].id == draggedNodeID { continue }
            
            nodes[i].x += nodes[i].vx * alpha
            nodes[i].y += nodes[i].vy * alpha
            
            nodes[i].vx *= friction
            nodes[i].vy *= friction
        }
        
        // Cool down
        alpha *= 0.965
    }
    
    // MARK: - Initializer & Helpers
    
    private func initializeGraph() {
        let activeNotes = store.notes
        
        // Build nodes
        nodes = activeNotes.map { note in
            let angle = Double.random(in: 0...(2 * .pi))
            let r = Double.random(in: 10...120)
            let x = cos(angle) * r
            let y = sin(angle) * r
            
            // Classify tags for color coding
            let primaryTag = selectPrimaryTag(from: note.tags)
            let color = colorForTag(primaryTag)
            
            return GraphNode(
                id: note.id,
                title: note.title.split(separator: "/").last.map(String.init) ?? note.title,
                tags: note.tags,
                x: x,
                y: y,
                color: color,
                primaryTag: primaryTag
            )
        }
        
        // Build edges
        var edgeList: [GraphEdge] = []
        for note in activeNotes {
            for outbound in note.outboundLinks {
                if activeNotes.contains(where: { $0.id == outbound }) {
                    let id = "\(note.id)-\(outbound)"
                    edgeList.append(GraphEdge(id: id, source: note.id, target: outbound))
                }
            }
        }
        edges = edgeList
        
        alpha = 1.0  // Start simulation
    }
    
    private func selectPrimaryTag(from tags: Set<String>) -> String? {
        if tags.contains("ai-context") { return "ai-context" }
        if tags.contains("guardrails") { return "guardrails" }
        if tags.contains(where: { $0.contains("project") }) { return "projects" }
        if tags.contains("system") { return "system" }
        return nil
    }
    
    private func colorForTag(_ tag: String?) -> Color {
        switch tag {
        case "ai-context":
            return Theme.violet
        case "guardrails":
            return Theme.accent
        case "projects":
            return Theme.brass
        case "system":
            return Theme.emerald
        default:
            return Theme.inkDim
        }
    }
    
    private func findNode(at point: CGPoint) -> GraphNode? {
        let hitRadius = 15.0 / zoom
        return nodes.first { node in
            let dx = node.x - point.x
            let dy = node.y - point.y
            return (dx*dx + dy*dy) <= (hitRadius * hitRadius)
        }
    }
    
    private func recenterGraph() {
        withAnimation(.easeOut(duration: 0.4)) {
            pan = .zero
            accumulatedPan = .zero
            zoom = 1.0
        }
        alpha = 1.0 // Re-heat layout
    }
    
    // MARK: - Subviews & Panels
    
    private var backgroundGrid: some View {
        GeometryReader { geometry in
            Path { path in
                let step = 40.0
                let width = geometry.size.width
                let height = geometry.size.height
                
                // Draw vertical lines
                for x in stride(from: 0.0, to: width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                
                // Draw horizontal lines
                for y in stride(from: 0.0, to: height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Theme.border.opacity(0.12), lineWidth: 0.5)
        }
    }
    
    private var tagLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAG CLUSTERS")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
                .padding(.bottom, 2)
            
            legendItem(label: "ai-context", color: Theme.violet)
            legendItem(label: "guardrails", color: Theme.accent)
            legendItem(label: "projects", color: Theme.brass)
            legendItem(label: "system notes", color: Theme.emerald)
        }
        .padding(12)
        .background(Theme.panel.opacity(0.75))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 6)))
    }
    
    private func legendItem(label: String, color: Color) -> some View {
        Button(action: {
            withAnimation {
                if filterTag == label || (label == "projects" && filterTag == "projects") {
                    filterTag = nil
                } else {
                    filterTag = label
                }
            }
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(filterTag == label ? Theme.ink : Theme.inkDim)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var controlsPanel: some View {
        HStack(spacing: 8) {
            Button(action: recenterGraph) {
                Image(systemName: "gobackward")
                    .font(.system(size: 11))
                Text("Recenter")
                    .font(.system(size: 10.5, design: .monospaced))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.ink)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            
            Text("Zoom: \(Int(zoom * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
                .padding(.leading, 4)
        }
        .padding(8)
        .background(Theme.panel.opacity(0.75))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 6)))
    }
    
    private func inspectorPanel(for node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(node.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                
                // Open note details view
                Button(action: {
                    store.selectNote(node.id)
                }) {
                    HStack(spacing: 4) {
                        Text("Open Note")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            
            if !node.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(node.tags.sorted(), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9.5, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(Theme.accent)
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(Theme.accent, lineWidth: 0.75))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.panel.opacity(0.85))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 8)))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// Helper to provide frosted glass effect on macOS
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
