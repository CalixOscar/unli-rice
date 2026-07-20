import Foundation

public enum ZipExportError: Error, CustomStringConvertible {
    case itemTooLarge(String)
    case invalidEntryName(String)

    public var description: String {
        switch self {
        case .itemTooLarge(let path):
            return "The export is too large for a standard Zip archive: \(path)"
        case .invalidEntryName(let path):
            return "The export contains a filename Zip cannot represent: \(path)"
        }
    }
}

/// A small, dependency-free Zip writer using the format's uncompressed
/// "stored" method. Keeping this in process is required by App Sandbox: a Mac
/// App Store app cannot launch `/usr/bin/ditto` to do the work on its behalf.
/// The result is a normal Zip archive readable by Finder and `unzip`.
public enum ZipExporter {
    private struct Entry {
        let name: String
        let data: Data
        let isDirectory: Bool
        let crc32: UInt32
        var localHeaderOffset: UInt32 = 0
    }

    public static func zip(directory: URL, to destination: URL) throws {
        var entries = try collectEntries(in: directory)
        var archive = Data()

        for index in entries.indices {
            guard archive.count <= Int(UInt32.max) else {
                throw ZipExportError.itemTooLarge(entries[index].name)
            }
            entries[index].localHeaderOffset = UInt32(archive.count)
            try appendLocalEntry(entries[index], to: &archive)
        }

        guard archive.count <= Int(UInt32.max) else {
            throw ZipExportError.itemTooLarge(destination.lastPathComponent)
        }
        let centralDirectoryOffset = UInt32(archive.count)
        for entry in entries {
            try appendCentralDirectoryEntry(entry, to: &archive)
        }
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

        guard entries.count <= Int(UInt16.max) else {
            throw ZipExportError.itemTooLarge("too many files")
        }
        archive.appendLittleEndian(UInt32(0x06054b50))
        archive.appendLittleEndian(UInt16(0)) // disk number
        archive.appendLittleEndian(UInt16(0)) // central-directory disk
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(centralDirectorySize)
        archive.appendLittleEndian(centralDirectoryOffset)
        archive.appendLittleEndian(UInt16(0)) // comment length

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try archive.write(to: destination, options: .atomic)
    }

    private static func collectEntries(in directory: URL) throws -> [Entry] {
        let fileManager = FileManager.default
        let rootName = directory.lastPathComponent + "/"
        var urls: [URL] = [directory]
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) {
            while let url = enumerator.nextObject() as? URL { urls.append(url) }
        }

        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            guard values.isDirectory == true || values.isRegularFile == true else { return nil }

            let relative: String
            if url == directory {
                relative = ""
            } else {
                relative = String(url.path.dropFirst(directory.path.count + 1))
            }
            let isDirectory = values.isDirectory == true
            let name = rootName + relative + (isDirectory && !relative.isEmpty ? "/" : "")
            guard !name.utf8.contains(0), name.utf8.count <= Int(UInt16.max) else {
                throw ZipExportError.invalidEntryName(name)
            }
            let data = isDirectory ? Data() : try Data(contentsOf: url)
            guard data.count <= Int(UInt32.max) else {
                throw ZipExportError.itemTooLarge(name)
            }
            return Entry(name: name, data: data, isDirectory: isDirectory, crc32: crc32(data))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func appendLocalEntry(_ entry: Entry, to archive: inout Data) throws {
        let name = Data(entry.name.utf8)
        archive.appendLittleEndian(UInt32(0x04034b50))
        archive.appendLittleEndian(UInt16(20)) // version needed
        archive.appendLittleEndian(UInt16(0x0800)) // UTF-8 names
        archive.appendLittleEndian(UInt16(0)) // stored, no compression
        archive.appendLittleEndian(UInt16(0)) // DOS time: midnight
        archive.appendLittleEndian(UInt16(0x0021)) // DOS date: 1980-01-01
        archive.appendLittleEndian(entry.crc32)
        archive.appendLittleEndian(UInt32(entry.data.count))
        archive.appendLittleEndian(UInt32(entry.data.count))
        archive.appendLittleEndian(UInt16(name.count))
        archive.appendLittleEndian(UInt16(0)) // extra length
        archive.append(name)
        archive.append(entry.data)
    }

    private static func appendCentralDirectoryEntry(_ entry: Entry, to archive: inout Data) throws {
        let name = Data(entry.name.utf8)
        archive.appendLittleEndian(UInt32(0x02014b50))
        archive.appendLittleEndian(UInt16(20)) // version made by
        archive.appendLittleEndian(UInt16(20)) // version needed
        archive.appendLittleEndian(UInt16(0x0800))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0x0021))
        archive.appendLittleEndian(entry.crc32)
        archive.appendLittleEndian(UInt32(entry.data.count))
        archive.appendLittleEndian(UInt32(entry.data.count))
        archive.appendLittleEndian(UInt16(name.count))
        archive.appendLittleEndian(UInt16(0)) // extra length
        archive.appendLittleEndian(UInt16(0)) // comment length
        archive.appendLittleEndian(UInt16(0)) // disk start
        archive.appendLittleEndian(UInt16(0)) // internal attributes
        archive.appendLittleEndian(entry.isDirectory ? UInt32(0x10) : UInt32(0))
        archive.appendLittleEndian(entry.localHeaderOffset)
        archive.append(name)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0)
            }
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
