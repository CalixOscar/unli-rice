import Foundation

public enum ShardFeedError: Error, LocalizedError, Equatable {
    case fileUnreadable(URL)
    case shardShrunk(url: URL, expectedMinOffset: UInt64, actualSize: UInt64)

    public var errorDescription: String? {
        switch self {
        case .fileUnreadable(let url):
            return "Shard file could not be read at \(url.path)"
        case .shardShrunk(let url, let expectedMinOffset, let actualSize):
            return "Shard file at \(url.path) shrunk from offset \(expectedMinOffset) to \(actualSize)."
        }
    }
}

/// Feed reading per-device JSON-Lines shard files.
public final class ShardFeed: EventFeed, @unchecked Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func readEvents(after cursor: FeedCursor?) throws -> (events: [Data], newCursor: FeedCursor) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ([], cursor ?? FeedCursor(offset: 0))
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let startOffset = cursor?.offset ?? 0

        // REFUSE a shrunk shard rather than resetting the cursor to 0
        if fileSize < startOffset {
            throw ShardFeedError.shardShrunk(url: fileURL, expectedMinOffset: startOffset, actualSize: fileSize)
        }

        guard fileSize > startOffset else {
            return ([], FeedCursor(offset: startOffset))
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: startOffset)
        let remainingData = try handle.readToEnd() ?? Data()

        // Stop at the last complete newline (0x0A)
        guard let lastNewlineIndex = remainingData.lastIndex(of: 0x0A) else {
            // Partial line with no newline yet -> leave cursor at startOffset
            return ([], FeedCursor(offset: startOffset))
        }

        let slice = remainingData[...lastNewlineIndex]

        var events: [Data] = []
        var currentOffset = startOffset

        var lineStart = slice.startIndex
        while lineStart <= lastNewlineIndex {
            guard let nextNewline = slice[lineStart...lastNewlineIndex].firstIndex(of: 0x0A) else {
                break
            }

            let lineData = slice[lineStart..<nextNewline]
            let lineLength = UInt64(nextNewline - lineStart + 1)

            let trimmed: Data
            if lineData.last == 0x0D {
                trimmed = lineData.dropLast()
            } else {
                trimmed = lineData
            }

            if trimmed.isEmpty {
                currentOffset += lineLength
                lineStart = nextNewline + 1
                continue
            }

            // STOP AT THE FIRST UNDECODABLE LINE — leave cursor before it
            guard isValidEventLine(trimmed) else {
                break
            }

            let fullLineData = Data(slice[lineStart...nextNewline])
            events.append(fullLineData)

            currentOffset += lineLength
            lineStart = nextNewline + 1
        }

        return (events, FeedCursor(offset: currentOffset))
    }

    private func isValidEventLine(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["id"] is String
    }
}
