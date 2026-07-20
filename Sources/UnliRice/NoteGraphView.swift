import SwiftUI
import UnliRiceCore

/// What the colours and the clusters mean.
///
/// Tag was the only option, and it was hardcoded to four tag names
/// (`ai-context`, `guardrails`, `projects`, `system`) chosen when the corpus was
/// eight notes old. On a real store most notes match none of them and land in a
/// single grey "default" cluster — a graph where 90% of the nodes are the same
/// colour is not grouped, it's just decorated.
///
/// These three answer questions that a note store actually raises: what is this
/// about, *who wrote it* (multiple LLMs write here concurrently — that's the
/// premise of the project), and *when*. Groups are derived from the notes
/// present, so the legend can never again describe a vocabulary the corpus
/// doesn't use.
enum GraphGrouping: String, CaseIterable, Identifiable {
    case tag
    case author
    case period

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tag: return "Tag"
        case .author: return "Author"
        case .period: return "Year/Month"
        }
    }

    /// The group one note belongs to, or nil for "ungrouped".
    func key(for note: Note) -> String? {
        switch self {
        case .tag:
            // Alphabetically first, so a note with the same tag set always lands
            // in the same group no matter what order Set iteration hands them
            // over in — otherwise nodes would swap colours between launches.
            return note.tags.sorted().first
        case .author:
            return note.creator
        case .period:
            return GraphGrouping.periodFormatter.string(from: note.createdAt)
        }
    }

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}

struct GraphNode: Identifiable, Equatable {
    let id: UUID
    let title: String
    let tags: Set<String>
    var x: Double
    var y: Double
    var vx: Double = 0
    var vy: Double = 0
    var color: Color
    /// Which group this node is in under the *current* grouping. Recomputed
    /// when the grouping changes; nil means the note has no value for it (no
    /// tags, say), which is a real state and renders grey rather than being
    /// forced into someone else's cluster.
    var group: String?

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
    @State private var filterGroup: String? = nil

    @State private var grouping: GraphGrouping = .tag
    /// Every group present, in a fixed order. Colour and cluster position are
    /// both derived from a group's index here, so both stay stable while the
    /// simulation runs — recomputing either from a `Set` would make nodes
    /// change colour on every tick.
    @State private var groupOrder: [String] = []
    /// One-shot: the graph frames itself when it first settles, and never
    /// again. Re-fitting on every cool-down would yank the view out from under
    /// someone who had deliberately zoomed into a corner.
    @State private var hasAutoFit = false
    
    // Physics constants
    private let charge: Double = -450.0       // repulsion force
    private let springStrength: Double = 0.05  // link attraction force
    private let restLength: Double = 130.0     // desired link length
    private let centerGravity: Double = 0.01   // pull to (0,0)
    private let clusterGravity: Double = 0.04  // pull to cluster centers
    private let friction: Double = 0.88

    /// How many nodes can carry a permanent label before the labels stop being
    /// readable. Eyeballed against the real store, where 190 of them cover the
    /// canvas edge to edge.
    private static let labelBudget = 60
    
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
                                let start = value.startLocation
                                let end = value.location
                                let dx = start.x - end.x
                                let dy = start.y - end.y
                                let dist = sqrt(dx*dx + dy*dy)
                                if dist < 5.0, let clickedNodeID = draggedNodeID {
                                    if selectedNodeID == clickedNodeID {
                                        store.selectNote(clickedNodeID)
                                    } else {
                                        selectedNodeID = clickedNodeID
                                    }
                                }
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
                    HStack(alignment: .top) {
                        groupLegend
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            controlsPanel(viewport: geometry.size)
                            Text("💡 Tip: Click selected node again to open note. Drag to move.")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Theme.inkDim.opacity(0.85))
                                .padding(.trailing, 8)
                        }
                    }
                    .padding(16)
                    
                    Spacer()
                    
                    if let selectedNode = nodes.first(where: { $0.id == selectedNodeID }) {
                        inspectorPanel(for: selectedNode)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            // Once the layout settles, frame it. On appear would fit the
            // random starting scatter rather than the graph, and never (the old
            // behaviour) left a large corpus spread past all four edges with no
            // control that could bring it back.
            //
            // It lives here, watching `alpha`, rather than inside `tickPhysics`
            // because this is where the canvas's real size is in scope. The
            // earlier attempt to stash that size in `@State` from `onAppear`
            // captured a zero and never updated, so the fit silently tripped its
            // own size guard on every call.
            .onAppear {
                initializeGraph()
                // The simulation needs a couple of seconds to stop moving, and
                // fitting before it settles frames the random starting scatter
                // instead of the graph. A fixed delay rather than watching
                // `alpha` cross its floor: hover and drag re-heat the
                // simulation, so "has cooled" is a state the user can postpone
                // indefinitely just by moving the mouse, and the one thing this
                // must not do is leave a large corpus spread past all four
                // edges with nothing framing it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard !hasAutoFit else { return }
                    hasAutoFit = true
                    fitToWindow(in: geometry.size)
                }
            }
        }
        .background(Theme.background)
        .onChange(of: grouping) { _ in
            withAnimation { applyGrouping() }
        }
        .onReceive(timer) { _ in
            tickPhysics()
        }
    }
    
    // MARK: - Canvas Rendering
    
    private func drawEdges(in context: GraphicsContext) {
        for edge in edges {
            guard let sourceNode = nodes.first(where: { $0.id == edge.source }),
                  let targetNode = nodes.first(where: { $0.id == edge.target }) else { continue }
            
            // An edge survives the filter if either end is in the group: a link
            // out of the group you're inspecting is information about it.
            let isFiltered = filterGroup != nil
                && sourceNode.group != filterGroup
                && targetNode.group != filterGroup
            
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
            let isFiltered = filterGroup != nil && node.group != filterGroup
            
            let baseColor = node.color

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
            
            // 5. Draw Labels with transparent black capsule backing.
            //
            // On a real corpus every node having a label is the same as no node
            // having one: 190 titles at fit-zoom overlap into a solid block of
            // text with the graph somewhere underneath it. Past `labelBudget`
            // the labels become an on-demand thing — hover, selection, or an
            // active group filter that has already narrowed the field.
            let inFocusedGroup = filterGroup != nil && !isFiltered
            let labelsAreLegible = nodes.count <= Self.labelBudget || inFocusedGroup
            if isHovered || isSelected || (labelsAreLegible && zoom > 0.65) {
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
            
            // Cluster pull toward this node's group centre.
            let target = clusterCenter(forGroup: node.group)
            nodes[i].vx += (target.x - node.x) * clusterGravity
            nodes[i].vy += (target.y - node.y) * clusterGravity
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
            
            return GraphNode(
                id: note.id,
                title: note.title.split(separator: "/").last.map(String.init) ?? note.title,
                tags: note.tags,
                x: x,
                y: y,
                // Both filled in by `applyGrouping` below, once every node
                // exists — a group's colour depends on how many notes are in it
                // relative to the others, which isn't knowable per-node.
                color: Theme.inkDim,
                group: nil
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
        applyGrouping()
        alpha = 1.0  // Start simulation
    }
    
    /// Six hues, cycled. Cycling is honest about the limit: past six groups the
    /// colours stop being unique, which is why the legend is clickable — colour
    /// narrows the field, clicking a legend entry is what actually isolates one
    /// group. Capping the *groups* instead (an "other" bucket) would hide
    /// exactly the long tail someone opens this view to find.
    private static let palette: [Color] = [
        Theme.accent, Theme.violet, Theme.brass, Theme.emerald, Theme.crit, Theme.ink
    ]

    private func color(forGroup group: String?) -> Color {
        guard let group, let index = groupOrder.firstIndex(of: group) else { return Theme.inkDim }
        return Self.palette[index % Self.palette.count]
    }

    /// Where a group's nodes are pulled towards. Evenly spaced on a circle, so
    /// the clusters are visually distinct for any number of groups — the old
    /// version had four hand-placed points and nowhere to put a fifth.
    private func clusterCenter(forGroup group: String?) -> CGPoint {
        guard let group, let index = groupOrder.firstIndex(of: group), groupOrder.count > 1 else {
            return .zero
        }
        let angle = (Double(index) / Double(groupOrder.count)) * 2 * .pi
        let radius = 90.0 + Double(groupOrder.count) * 12.0
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }

    /// Reassigns every node's group and colour without rebuilding the layout.
    /// Switching Tag → Author should recolour and re-cluster the graph you're
    /// looking at, not scatter it and start the simulation from random
    /// positions again — the point is to see the *same* notes regroup.
    private func applyGrouping() {
        let notesByID = Dictionary(uniqueKeysWithValues: store.notes.map { ($0.id, $0) })
        let keys = store.notes.compactMap { grouping.key(for: $0) }
        groupOrder = Array(Set(keys)).sorted { lhs, rhs in
            // Frequency first: the biggest groups get the most distinct hues,
            // and a one-note group never displaces a forty-note one.
            let lhsCount = keys.filter { $0 == lhs }.count
            let rhsCount = keys.filter { $0 == rhs }.count
            return lhsCount == rhsCount ? lhs < rhs : lhsCount > rhsCount
        }

        for index in nodes.indices {
            let group = notesByID[nodes[index].id].flatMap { grouping.key(for: $0) }
            nodes[index].group = group
            nodes[index].color = color(forGroup: group)
        }
        if let filterGroup, !groupOrder.contains(filterGroup) { self.filterGroup = nil }
        alpha = 1.0
    }

    /// Zooms and pans so every node is on screen.
    ///
    /// "Recenter" only ever reset to 100% at the origin, which fits a graph
    /// exactly when the layout happens to be smaller than the window — on a
    /// corpus of any size the force simulation spreads well past the viewport
    /// and there was no way back except pinching. This solves for the actual
    /// bounding box instead.
    private func fitToWindow(in size: CGSize) {
        guard !nodes.isEmpty, size.width > 0, size.height > 0 else { return }

        let minX = nodes.map(\.x).min() ?? 0
        let maxX = nodes.map(\.x).max() ?? 0
        let minY = nodes.map(\.y).min() ?? 0
        let maxY = nodes.map(\.y).max() ?? 0

        // The bounds above are node *centres*. What actually overflows the
        // window is whatever is drawn around them, and that differs by an order
        // of magnitude depending on whether labels are showing: a title like
        // "Session: Prepare app for TestFlight and App Store submission" is
        // ~400pt of text drawn centred under a 24pt dot. Padding for labels
        // that aren't being drawn (the >60-node case) just zooms out for no
        // reason, so the allowance follows the same rule the labels do.
        let labelled = nodes.count <= Self.labelBudget
        let horizontalPad = labelled ? 400.0 : 120.0
        let verticalPad = labelled ? 180.0 : 90.0
        let width = (maxX - minX) + horizontalPad
        let height = (maxY - minY) + verticalPad

        let scale = min(size.width / max(width, 1), size.height / max(height, 1))
        let targetZoom = max(0.15, min(4.0, scale))

        // The layout's centre of mass, moved to the viewport's centre. Without
        // this a graph that drifted off to one side would be scaled to fit and
        // still sit half outside the window.
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        withAnimation(.easeOut(duration: 0.45)) {
            zoom = targetZoom
            pan = CGSize(width: -centerX * targetZoom, height: -centerY * targetZoom)
            accumulatedPan = pan
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
    
    /// Built from the groups actually present, not from a fixed list of four
    /// tag names. Scrolls, because "Year/Month" on a two-year-old store is a
    /// couple of dozen entries and the panel can't grow past the window.
    private var groupLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(grouping.displayName.uppercased()) CLUSTERS")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
                .padding(.bottom, 2)

            if groupOrder.isEmpty {
                Text("nothing to group by")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.inkDim)
            } else {
                // The scroller is only introduced once the list would overflow.
                // A ScrollView always claims the height it's offered, so using
                // one unconditionally left a mostly-empty 220pt panel floating
                // over the graph for a corpus with three authors.
                let entries = VStack(alignment: .leading, spacing: 6) {
                    ForEach(groupOrder, id: \.self) { group in
                        legendItem(label: group, color: color(forGroup: group))
                    }
                }
                if groupOrder.count > 10 {
                    ScrollView { entries }.frame(height: 220)
                } else {
                    entries
                }
            }
        }
        .padding(12)
        .frame(width: 180, alignment: .leading)
        .background(Theme.panel.opacity(0.75))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 6)))
    }

    private func legendItem(label: String, color: Color) -> some View {
        Button(action: {
            withAnimation {
                filterGroup = (filterGroup == label) ? nil : label
            }
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))

                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(filterGroup == label ? Theme.ink : Theme.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func controlsPanel(viewport: CGSize) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: $grouping) {
                ForEach(GraphGrouping.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)

            // Fit before Recenter: it's the one you want after the simulation
            // has thrown the layout past the edges of the window, which is most
            // of the time on a real corpus.
            controlButton("Fit", icon: "arrow.down.right.and.arrow.up.left") {
                // The size comes straight from the enclosing GeometryReader
                // rather than from `viewportSize`. Both should agree, but this
                // path cannot be wrong: it is the size SwiftUI just laid the
                // canvas out at, not a value that had to survive a state write.
                fitToWindow(in: viewport)
            }
            controlButton("Recenter", icon: "gobackward", action: recenterGraph)

            Text("\(Int(zoom * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.inkDim)
        }
        .padding(8)
        .background(Theme.panel.opacity(0.75))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).clipShape(RoundedRectangle(cornerRadius: 6)))
    }

    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10.5, design: .monospaced))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .foregroundStyle(Theme.ink)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
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
