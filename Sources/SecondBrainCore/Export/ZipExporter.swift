import Foundation

public enum ZipExportError: Error, CustomStringConvertible {
    case processFailed(Int32, String)

    public var description: String {
        switch self {
        case .processFailed(let code, let output):
            return "ditto exited with code \(code): \(output)"
        }
    }
}

/// Zips a directory. Shells out to `ditto`, which ships with every Mac —
/// avoids pulling in a compression library for one feature.
public enum ZipExporter {
    public static func zip(directory: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", "--norsrc", directory.path, destination.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw ZipExportError.processFailed(process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
