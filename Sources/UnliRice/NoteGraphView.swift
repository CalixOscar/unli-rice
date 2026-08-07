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
    case project
    case category
    case tag
    case author
    case period

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .project: return "Project"
        case .category: return "Category"
        case .tag: return "Tag"
        case .author: return "Author"
        case .period: return "Year/Month"
        }
    }

    /// The group one note belongs to, or nil for "ungrouped".
    func key(for note: Note) -> String? {
        switch self {
        case .project:
            if let proj = Retrospective.project(of: note) {
                return proj
            }
            if note.title.hasPrefix("Doc: ") {
                let parts = note.title.dropFirst(5).split(separator: "/")
                if parts.count > 1 {
                    return String(parts[0])
                }
            }
            if note.title.hasPrefix("Profile:") { return "Profiles" }
            if note.title.hasPrefix("Wiki:") { return "Wiki" }
            if note.title.hasPrefix("Session:") { return "Sessions" }
            if note.tags.contains("document") { return "Ingested Docs" }
            return "General Notes"

        case .category:
            let title = note.title
            if title.hasPrefix("Profile:") || title.hasPrefix("House Rules") { return "Profiles & Rules" }
            if title.hasPrefix("Wiki:") { return "Wiki Hubs" }
            if title.hasPrefix("Session:") { return "AI Sessions" }
            if title.hasPrefix("Doc:") || note.tags.contains("document") { return "Raw Notes & Docs" }
            if title.hasPrefix("Project:") || note.tags.contains("project") { return "Projects" }
            return "User Notes"

        case .tag:
            // Prefer specific meaningful tags over generic machine tags like "document" or "ingested"
            let specific = note.tags.filter { $0 != "document" && $0 != "ingested" }.sorted()
            return specific.first ?? note.tags.sorted().first

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

extension NoteGraphView {
    /// "July 2026" — the grow replay's on-screen clock.
    static let replayCaptionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

struct GraphNode: Identifiable, Equatable {
    let id: UUID
    let title: String
    let tags: Set<String>
    /// When the note was created — the ordering the grow replay walks.
    let createdAt: Date
    var x: Double
    var y: Double
    var vx: Double = 0
    var vy: Double = 0
    var color: Color
    /// Links touching this node, in either direction. Drives node size: hub
    /// notes render larger, so the brain's centres are visible at a glance.
    var degree: Int = 0
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

    @State private var grouping: GraphGrouping = .project
    /// Every group present, in a fixed order. Colour and cluster position are
    /// both derived from a group's index here, so both stay stable while the
    /// simulation runs — recomputing either from a `Set` would make nodes
    /// change colour on every tick.
    @State private var groupOrder: [String] = []
    /// One-shot: the graph frames itself when it first settles, and never
    /// again. Re-fitting on every cool-down would yank the view out from under
    /// someone who had deliberately zoomed into a corner.
    @State private var hasAutoFit = false

    // Grow replay: animates the brain being built note-by-note in creation
    // order. `revealedIDs == nil` means not replaying — everything shows.
    // A Set rather than a count-prefix so reveal order and node order stay
    // independent; nodes are never re-sorted mid-simulation.
    @State private var revealedIDs: Set<UUID>? = nil
    @State private var replayQueue: [UUID] = []
    @State private var replayTick: Int = 0
    /// Creation date of the most recently revealed note — the replay's clock,
    /// shown as a caption while the brain grows.
    @State private var replayDate: Date? = nil

    private var isReplaying: Bool { revealedIDs != nil }

    private func isRevealed(_ id: UUID) -> Bool {
        revealedIDs?.contains(id) ?? true
    }
    
    // Physics constants for Star Map Constellation layout
    private let charge: Double = -180.0        // Repulsion force (mild so nodes don't blow past their cluster)
    private let springStrength: Double = 0.08  // Link attraction force
    private let restLength: Double = 85.0      // Desired link length
    private let centerGravity: Double = 0.003  // Slight global pull
    private let clusterGravity: Double = 0.28  // Strong pull to constellation sector centers
    private let friction: Double = 0.80        // High friction for fast settling

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
                    
                    // Draw Star Map Constellation Sectors & Nebulae
                    drawConstellationBackground(in: context)

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
                            if let draggedNodeID {
                                let canvasX = (value.location.x - center.x - accumulatedPan.width) / zoom
                                let canvasY = (value.location.y - center.y - accumulatedPan.height) / zoom
                                if let idx = nodes.firstIndex(where: { $0.id == draggedNodeID }) {
                                    nodes[idx].x = canvasX
                                    nodes[idx].y = canvasY
                                    alpha = max(alpha, 0.3)  // Gentle re-heat during drag
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
                                // A click on empty canvas (not a pan) clears the
                                // selection — with neighbor-dimming active there
                                // has to be a way back to the whole map.
                                let dx = value.startLocation.x - value.location.x
                                let dy = value.startLocation.y - value.location.y
                                if sqrt(dx*dx + dy*dy) < 5.0, selectedNodeID != nil {
                                    withAnimation { selectedNodeID = nil }
                                }
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
                // Pinch-to-zoom support (pure view transform, no physics re-heat)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = max(0.15, min(4.0, value))
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
                                .foregroundStyle(Theme.textSecondary.opacity(0.85))
                                .padding(.trailing, 8)
                        }
                    }
                    .padding(16)

                    Spacer()

                    // The replay's clock: which month of the corpus's life is
                    // currently being written onto the canvas.
                    if isReplaying, let replayDate {
                        VStack(spacing: 3) {
                            Text(Self.replayCaptionFormatter.string(from: replayDate))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(revealedIDs?.count ?? 0) of \(nodes.count) notes")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .liquidGlass(cornerRadius: 8)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                    }

                    if let selectedNode = nodes.first(where: { $0.id == selectedNodeID }) {
                        inspectorPanel(for: selectedNode)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                if nodes.isEmpty {
                    VStack(spacing: 12) {
                        Text("Your brain map is empty")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Every note becomes a dot here, and every [[link]] between notes becomes a line.\nAs your AI tools write and cross-link notes, this grows into a map of what they know.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)

                        Button("+ Add Folder of .md Files or Projects") {
                            store.chooseScanRoot()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(24)
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
        .background(Theme.bgMain)
        .onChange(of: grouping) { _ in
            withAnimation { applyGrouping() }
        }
        .onChange(of: store.notes.count) { _ in
            initializeGraph()
        }
        .onReceive(timer) { _ in
            advanceReplay()
            tickPhysics()
        }
    }
    
    // MARK: - Canvas Rendering

    /// Every node one link away from the current selection, in either
    /// direction. Direction is deliberately ignored: a backlink and an outbound
    /// link are the same fact about the *pair* of notes, and the map is about
    /// which notes belong together, not who wrote the `[[..]]` first.
    private var selectedNeighborIDs: Set<UUID> {
        guard let selectedNodeID else { return [] }
        var ids: Set<UUID> = []
        for edge in edges {
            if edge.source == selectedNodeID { ids.insert(edge.target) }
            if edge.target == selectedNodeID { ids.insert(edge.source) }
        }
        return ids
    }

    private func drawEdges(in context: GraphicsContext) {
        for edge in edges {
            // During the grow replay an edge only exists once both of its notes
            // do — a line to a not-yet-born note would spoil the story.
            guard isRevealed(edge.source), isRevealed(edge.target) else { continue }
            guard let sourceNode = nodes.first(where: { $0.id == edge.source }),
                  let targetNode = nodes.first(where: { $0.id == edge.target }) else { continue }

            // An edge survives the filter if either end is in the group: a link
            // out of the group you're inspecting is information about it.
            let isFiltered = filterGroup != nil
                && sourceNode.group != filterGroup
                && targetNode.group != filterGroup

            let touchesSelection = selectedNodeID != nil
                && (edge.source == selectedNodeID || edge.target == selectedNodeID)

            var path = Path()
            path.move(to: CGPoint(x: sourceNode.x, y: sourceNode.y))
            path.addLine(to: CGPoint(x: targetNode.x, y: targetNode.y))

            if isFiltered {
                context.stroke(path, with: .color(Color.gray.opacity(0.04)), lineWidth: 0.5)
            } else if touchesSelection {
                // The selected note's own links are the whole story while a
                // selection is active — they get the brightest stroke on screen.
                let edgeColor = sourceNode.color
                context.stroke(path, with: .color(edgeColor.opacity(0.22)), lineWidth: 5.0)
                context.stroke(path, with: .color(edgeColor.opacity(0.75)), lineWidth: 1.6)
            } else if selectedNodeID != nil {
                // Everything not connected to the selection recedes rather than
                // disappears: the rest of the brain stays visible as context.
                context.stroke(path, with: .color(Color.gray.opacity(0.06)), lineWidth: 0.75)
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
        let neighbors = selectedNeighborIDs
        for node in nodes {
            guard isRevealed(node.id) else { continue }
            let radius = radius(for: node)
            let isHovered = hoveredNodeID == node.id
            let isSelected = selectedNodeID == node.id
            let isNeighbor = neighbors.contains(node.id)
            // Two ways to recede: outside the active legend filter, or outside
            // the selected note's neighborhood. Both render the same — dim but
            // present — because both mean "not what you're looking at right now".
            let isFiltered = (filterGroup != nil && node.group != filterGroup)
                || (selectedNodeID != nil && !isSelected && !isNeighbor)

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
            // A neighbor's label always draws while a note is selected: "what
            // is this connected to" is the question a selection asks, and the
            // handful of linked notes is well under any label budget.
            if isHovered || isSelected || isNeighbor || (labelsAreLegible && zoom > 0.65) {
                if !isFiltered || isSelected {
                    let labelText = Text(node.title)
                        .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium, design: .monospaced))
                        .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    
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
            // Unrevealed nodes sit out the replay entirely — exerting force
            // from an invisible node would shape the layout around ghosts.
            guard isRevealed(nodes[i].id) else { continue }
            for j in stride(from: i + 1, to: nodeCount, by: step) {
                guard isRevealed(nodes[j].id) else { continue }
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
            guard isRevealed(edge.source), isRevealed(edge.target) else { continue }
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
            guard isRevealed(node.id) else { continue }

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
            guard isRevealed(nodes[i].id) else { continue }
            
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
                createdAt: note.createdAt,
                x: x,
                y: y,
                // Both filled in by `applyGrouping` below, once every node
                // exists — a group's colour depends on how many notes are in it
                // relative to the others, which isn't knowable per-node.
                color: Theme.textSecondary,
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

        var degreeByID: [UUID: Int] = [:]
        for edge in edgeList {
            degreeByID[edge.source, default: 0] += 1
            degreeByID[edge.target, default: 0] += 1
        }
        for index in nodes.indices {
            nodes[index].degree = degreeByID[nodes[index].id] ?? 0
        }

        applyGrouping()
        alpha = 1.0  // Start simulation
    }

    // MARK: - Grow Replay

    private func startGrowReplay() {
        guard nodes.count > 1 else { return }
        replayQueue = nodes.sorted { $0.createdAt < $1.createdAt }.map(\.id)
        revealedIDs = []
        replayTick = 0
        selectedNodeID = nil
        filterGroup = nil
        alpha = 1.0
        revealNextNode()
    }

    private func stopGrowReplay() {
        revealedIDs = nil
        replayQueue = []
        replayDate = nil
        // Gentle re-heat so late arrivals that spawned on top of a neighbor
        // spread out instead of freezing mid-overlap.
        alpha = max(alpha, 0.5)
    }

    /// Called from the physics timer, so replay speed is defined in ticks. The
    /// interval is derived from corpus size: the whole replay should take ~8
    /// seconds whether the store holds 20 notes or 500 — it's a story beat,
    /// not a progress bar.
    private func advanceReplay() {
        guard isReplaying, !replayQueue.isEmpty else { return }
        replayTick += 1
        let totalTicks = 480  // 8 seconds at 60fps
        let interval = max(2, totalTicks / max(nodes.count, 1))
        if replayTick % interval == 0 {
            revealNextNode()
        }
    }

    private func revealNextNode() {
        guard var revealed = revealedIDs, !replayQueue.isEmpty else { return }
        let id = replayQueue.removeFirst()

        if let idx = nodes.firstIndex(where: { $0.id == id }) {
            // Spawn beside an already-revealed neighbor when one exists: a new
            // note visibly buds off the part of the brain it links to, rather
            // than teleporting in at its final resting place.
            let neighborIDs = edges.compactMap { edge -> UUID? in
                if edge.source == id { return edge.target }
                if edge.target == id { return edge.source }
                return nil
            }
            if let anchorID = neighborIDs.first(where: { revealed.contains($0) }),
               let anchor = nodes.first(where: { $0.id == anchorID }) {
                nodes[idx].x = anchor.x + Double.random(in: -35...35)
                nodes[idx].y = anchor.y + Double.random(in: -35...35)
            }
            nodes[idx].vx = 0
            nodes[idx].vy = 0
            replayDate = nodes[idx].createdAt
        }

        revealed.insert(id)
        revealedIDs = revealed
        // Keep the simulation warm for the whole replay: each arrival should
        // nudge the layout, and a cooled graph would stack arrivals in place.
        alpha = max(alpha, 0.45)

        if replayQueue.isEmpty {
            // Fully grown. Linger a moment so the final date is readable, then
            // return to the normal (non-replay) state.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if replayQueue.isEmpty { stopGrowReplay() }
            }
        }
    }

    /// Node radius grows with the square root of its link count — sqrt because
    /// what should scale with importance is *area*, and a linear radius would
    /// make a 25-link hub dwarf the canvas. Capped so the real corpus's biggest
    /// hub stays a node rather than becoming a backdrop.
    private func radius(for node: GraphNode) -> Double {
        9.0 + min(13.0, 2.5 * sqrt(Double(node.degree)))
    }
    
    /// Six hues, cycled. Cycling is honest about the limit: past six groups the
    /// colours stop being unique, which is why the legend is clickable — colour
    /// narrows the field, clicking a legend entry is what actually isolates one
    /// group. Capping the *groups* instead (an "other" bucket) would hide
    /// exactly the long tail someone opens this view to find.
    private static let palette: [Color] = [
        Theme.accentColor, Theme.violet, Theme.brass, Theme.emerald, Theme.crit, Theme.textPrimary
    ]

    private func color(forGroup group: String?) -> Color {
        guard let group, let index = groupOrder.firstIndex(of: group) else { return Theme.textSecondary }
        return Self.palette[index % Self.palette.count]
    }

    /// Star Map sector background rendering
    private func drawConstellationBackground(in context: GraphicsContext) {
        for group in groupOrder {
            let center = clusterCenter(forGroup: group)
            let color = color(forGroup: group)

            // 1. Glowing Nebula Background
            let nebulaRadius = 240.0
            let nebulaRect = CGRect(x: center.x - nebulaRadius, y: center.y - nebulaRadius, width: nebulaRadius * 2, height: nebulaRadius * 2)
            let shading = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [color.opacity(0.12), color.opacity(0.03), .clear]),
                center: center,
                startRadius: 0,
                endRadius: nebulaRadius
            )
            context.fill(Path(ellipseIn: nebulaRect), with: shading)

            // 2. Constellation Orbit Ring
            var ringPath = Path()
            ringPath.addEllipse(in: CGRect(x: center.x - 170.0, y: center.y - 170.0, width: 340.0, height: 340.0))
            let strokeStyle = StrokeStyle(lineWidth: 1.0, dash: [4, 6])
            context.stroke(ringPath, with: .color(color.opacity(0.18)), style: strokeStyle)

            // 3. Sector Title Label
            let titleText = Text("✨ \(group.uppercased()) SECTOR")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color.opacity(0.85))
            let resolved = context.resolve(titleText)
            context.draw(resolved, at: CGPoint(x: center.x, y: center.y - 185.0), anchor: .bottom)
        }
    }

    /// Sector centers for Star Map Constellation journey.
    private func clusterCenter(forGroup group: String?) -> CGPoint {
        guard let group else { return .zero }

        switch group {
        case "Profiles & Rules", "Profiles":
            return CGPoint(x: 0, y: 0) // Center core
        case "Raw Notes & Docs", "Ingested Docs":
            return CGPoint(x: -480, y: -290) // Top-Left Sector
        case "Projects", "Unli Rice":
            return CGPoint(x: 480, y: -290) // Top-Right Sector
        case "AI Sessions", "Sessions":
            return CGPoint(x: 480, y: 290) // Bottom-Right Sector
        case "Wiki Hubs", "Wiki":
            return CGPoint(x: -480, y: 290) // Bottom-Left Sector
        case "User Notes", "General Notes":
            return CGPoint(x: 0, y: 400) // South Sector
        default:
            if let index = groupOrder.firstIndex(of: group), groupOrder.count > 1 {
                let angle = (Double(index) / Double(groupOrder.count)) * 2 * .pi
                let radius = 450.0 + Double(index % 3) * 80.0
                return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            }
            return .zero
        }
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
        return nodes.first { node in
            guard isRevealed(node.id) else { return false }
            // At least the drawn circle, but never smaller than 15 *screen*
            // pixels — small nodes stay clickable when zoomed out.
            let hitRadius = max(radius(for: node) + 3.0, 15.0 / zoom)
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
            .stroke(Theme.borderLight.opacity(0.12), lineWidth: 0.5)
        }
    }
    
    /// Built from the groups actually present, not from a fixed list of four
    /// tag names. Scrolls, because "Year/Month" on a two-year-old store is a
    /// couple of dozen entries and the panel can't grow past the window.
    private var groupLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(grouping.displayName.uppercased()) CLUSTERS")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 2)

            if groupOrder.isEmpty {
                Text("nothing to group by")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
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
        .liquidGlass(cornerRadius: 6)
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
                    .foregroundStyle(filterGroup == label ? Theme.textPrimary : Theme.textSecondary)
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
            .frame(width: 330)

            // Grow replays the corpus being written note-by-note, oldest
            // first — the "watch the brain build itself" button.
            controlButton(isReplaying ? "Stop" : "Grow", icon: isReplaying ? "stop.fill" : "play.fill") {
                if isReplaying {
                    stopGrowReplay()
                } else {
                    startGrowReplay()
                }
            }

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

            controlButton("Add Folder", icon: "folder.badge.plus") {
                store.chooseScanRoot()
            }

            Text("\(Int(zoom * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(8)
        .liquidGlass(cornerRadius: 6)
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
        .foregroundStyle(Theme.onSolidFill)
        .solidControl(cornerRadius: 4)
    }

    private func inspectorPanel(for node: GraphNode) -> some View {
        // The neighborhood, resolved to actual nodes so the chips below can
        // carry titles and be clicked to walk the graph link by link.
        let linkedNodes = selectedNeighborIDs
            .compactMap { id in nodes.first(where: { $0.id == id }) }
            .sorted { $0.title < $1.title }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(node.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
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
                    .foregroundStyle(Theme.accentColor)
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
                            .foregroundStyle(Theme.accentColor)
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(Theme.accentColor, lineWidth: 0.75))
                    }
                }
            }

            if linkedNodes.isEmpty {
                Text("Not linked to any other note yet — link notes with [[title]] and they show up here.")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LINKED TO \(linkedNodes.count) NOTE\(linkedNodes.count == 1 ? "" : "S")")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)

                    // Wrapping would be nicer than one scrolling row, but a
                    // horizontal scroller is what fits in a fixed-height panel
                    // pinned to the bottom of the canvas.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(linkedNodes) { linked in
                                Button(action: {
                                    withAnimation { selectedNodeID = linked.id }
                                }) {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(linked.color)
                                            .frame(width: 6, height: 6)
                                        Text(linked.title)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .overlay(RoundedRectangle(cornerRadius: 999).stroke(Theme.borderLight, lineWidth: 0.75))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 8)
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
