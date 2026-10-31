import Foundation

public enum ProjectIcon {
    public static func find(in folder: URL, fileManager: FileManager = .default, maxDepth: Int = 6, maxEntries: Int = 10_000) -> URL? {
        struct Candidate {
            let url: URL
            let rank: Int
            let depth: Int
            let width: UInt32
        }

        let skipped = Set(["node_modules", "build", "Build", "DerivedData", "Pods", "Carthage", "dist", "vendor", "_archive"])
        var queue: [(URL, Int)] = [(folder, 0)]
        var index = 0
        var seen = 0
        var candidates: [Candidate] = []
        while index < queue.count && seen < maxEntries {
            let (directory, depth) = queue[index]
            index += 1
            guard depth < maxDepth,
                  let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { continue }
            for child in children {
                guard seen < maxEntries else { break }
                seen += 1
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                let childDepth = depth + 1
                if values.isDirectory == true {
                    let name = child.lastPathComponent
                    if !name.hasPrefix("."), !skipped.contains(name), !["app", "xcarchive"].contains(child.pathExtension.lowercased()), childDepth < maxDepth {
                        queue.append((child, childDepth))
                    }
                    continue
                }
                let name = child.lastPathComponent.lowercased()
                let ext = child.pathExtension.lowercased()
                let rank: Int
                if ext == "png" && child.deletingLastPathComponent().lastPathComponent.lowercased() == "appicon.appiconset" { rank = 0 }
                else if ext == "icns" { rank = 1 }
                else if ["icon.png", "logo.png", "apple-touch-icon.png", "favicon.png"].contains(name) { rank = 2 }
                else if name == "favicon.ico" { rank = 3 }
                else { continue }
                var width: UInt32 = 0
                if rank == 0 {
                    let handle = try? FileHandle(forReadingFrom: child)
                    let data = (try? handle?.read(upToCount: 24)) ?? nil
                    try? handle?.close()
                    if let data, data.count >= 24,
                       Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] {
                    width = data[16..<20].reduce(0) { ($0 << 8) | UInt32($1) }
                    }
                }
                candidates.append(Candidate(url: child, rank: rank, depth: childDepth, width: width))
            }
        }
        return candidates.sorted {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.rank == 0 && $0.width != $1.width { return $0.width > $1.width }
            return $0.url.path < $1.url.path
        }.first?.url
    }
}
