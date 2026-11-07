import Foundation

public enum EventCausalOrder {
    private struct ReadyHeap {
        private struct Entry {
            let id: UUID
            let timestamp: Date
            let key: String
        }
        private var entries: [Entry] = []
        private static func less(_ lhs: Entry, _ rhs: Entry) -> Bool {
            lhs.timestamp == rhs.timestamp ? lhs.key < rhs.key : lhs.timestamp < rhs.timestamp
        }
        mutating func push(_ event: Event) {
            entries.append(Entry(id: event.id, timestamp: event.timestamp, key: event.id.uuidString))
            var index = entries.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard Self.less(entries[index], entries[parent]) else { break }
                entries.swapAt(index, parent); index = parent
            }
        }
        mutating func pop() -> UUID? {
            guard !entries.isEmpty else { return nil }
            if entries.count == 1 { return entries.removeLast().id }
            let result = entries[0].id
            entries[0] = entries.removeLast()
            var index = 0
            while true {
                let left = index * 2 + 1, right = left + 1
                guard left < entries.count else { break }
                let child = right < entries.count && Self.less(entries[right], entries[left]) ? right : left
                guard Self.less(entries[child], entries[index]) else { break }
                entries.swapAt(child, index); index = child
            }
            return result
        }
    }
    public struct Result {
        public let ordered: [Event]
        public let pending: Set<UUID>
        public let conflictedNoteIDs: Set<UUID>
    }
    /// Pure replay: orphan declarations are inert, and missing semantic parents
    /// remain pending. Conflicts are reported only for actual directed cycles.
    public static func order(_ events: [Event]) -> Result {
        let semantic = events.filter { $0.kind != .causalOrder }
        let byID = Dictionary(semantic.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var parents: [UUID: Set<UUID>] = [:]
        var declared = Set<UUID>()
        var malformedNotes = Set<UUID>()
        var malformedEvents = Set<UUID>()
        var causalNotes = Set<UUID>()
        for event in semantic {
            if let links = event.causalParents { causalNotes.insert(event.noteId); declared.insert(event.id); parents[event.id, default: []].formUnion(links) }
        }
        for declaration in events where declaration.kind == .causalOrder {
            guard let target = declaration.relatedEventId, let event = byID[target] else { continue }
            causalNotes.insert(event.noteId)
            guard event.noteId == declaration.noteId else {
                malformedNotes.formUnion([event.noteId, declaration.noteId]); malformedEvents.insert(target); continue
            }
            guard let links = declaration.causalParents else {
                malformedNotes.insert(event.noteId); malformedEvents.insert(target); continue
            }
            declared.insert(target); parents[target, default: []].formUnion(links)
        }
        let causal = !causalNotes.isEmpty
        if !causal {
            let ordered = semantic.enumerated().sorted { a, b in
                a.element.timestamp == b.element.timestamp ? a.offset < b.offset : a.element.timestamp < b.element.timestamp
            }.map(\.element)
            return Result(ordered: ordered, pending: [], conflictedNoteIDs: [])
        }
        // Unrelated legacy-only notes keep their stable per-note input order.
        var previous: [UUID: UUID] = [:]
        for (_, event) in semantic.enumerated().sorted(by: { a, b in
            a.element.timestamp == b.element.timestamp ? a.offset < b.offset : a.element.timestamp < b.element.timestamp
        }) where !causalNotes.contains(event.noteId) {
            declared.insert(event.id)
            if let prior = previous[event.noteId] { parents[event.id, default: []].insert(prior) }
            previous[event.noteId] = event.id
        }
        // Build both graph directions once; missing parents remain unresolved.
        var forward: [UUID: [UUID]] = [:], reverse: [UUID: [UUID]] = [:]
        for event in semantic {
            for parent in parents[event.id, default: []] {
                guard let ancestor = byID[parent] else { continue }
                if ancestor.noteId != event.noteId {
                    malformedNotes.insert(event.noteId); malformedEvents.insert(event.id)
                }
                forward[event.id, default: []].append(parent)
                reverse[parent, default: []].append(event.id)
            }
        }
        // Iterative Kosaraju avoids per-node reachability scans and stack overflow.
        var visited = Set<UUID>(), finish: [UUID] = []
        for start in byID.keys where visited.insert(start).inserted {
            var stack: [(UUID, Int)] = [(start, 0)]
            while !stack.isEmpty {
                let index = stack.count - 1, id = stack[index].0, next = stack[index].1
                let edges = forward[id, default: []]
                if next < edges.count {
                    stack[index].1 += 1
                    let child = edges[next]
                    if visited.insert(child).inserted { stack.append((child, 0)) }
                } else { finish.append(id); stack.removeLast() }
            }
        }
        visited.removeAll()
        var cycleIDs = Set<UUID>()
        for start in finish.reversed() where visited.insert(start).inserted {
            var stack = [start], component: [UUID] = []
            while let id = stack.popLast() {
                component.append(id)
                for child in reverse[id, default: []] where visited.insert(child).inserted { stack.append(child) }
            }
            if component.count > 1 || forward[start, default: []].contains(start) { cycleIDs.formUnion(component) }
        }
        malformedNotes.formUnion(cycleIDs.compactMap { byID[$0]?.noteId })
        var pending = Set(semantic.filter { !declared.contains($0.id) }.map(\.id))
        pending.formUnion(cycleIDs); pending.formUnion(malformedEvents)
        for event in semantic where parents[event.id, default: []].contains(where: { byID[$0] == nil }) { pending.insert(event.id) }
        var queue = Array(pending), cursor = 0
        while cursor < queue.count {
            let id = queue[cursor]; cursor += 1
            for child in reverse[id, default: []] where pending.insert(child).inserted { queue.append(child) }
        }
        let eligible = Set(byID.keys).subtracting(pending)
        var indegree: [UUID: Int] = [:], children: [UUID: [UUID]] = [:]
        for id in eligible {
            let dependencies = parents[id, default: []].intersection(eligible)
            indegree[id] = dependencies.count
            for parent in dependencies { children[parent, default: []].append(id) }
        }
        var ready = ReadyHeap(), ordered: [Event] = []
        for id in eligible where indegree[id] == 0 { ready.push(byID[id]!) }
        while let id = ready.pop() {
            ordered.append(byID[id]!)
            for child in children[id, default: []] {
                indegree[child, default: 0] -= 1
                if indegree[child] == 0 { ready.push(byID[child]!) }
            }
        }
        pending.subtract(cycleIDs)
        return Result(ordered: ordered, pending: pending, conflictedNoteIDs: malformedNotes)
    }
}
