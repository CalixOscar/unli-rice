import Foundation

/// Minimal JSON-RPC 2.0 and JSON Serialization helpers shared across MCP and CLI tools.
public enum JSONRPC {
    public static func parseLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func writeLine(_ object: [String: Any], to handle: FileHandle = .standardOutput) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        handle.write(data)
        handle.write("\n".data(using: .utf8)!)
    }

    public static func result(id: Any?, _ payload: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": payload]
    }

    public static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    /// Encodes any Encodable value into a JSON-Serialization-compatible `Any`
    /// so it can be embedded into a JSON response dictionary or serialized to stdout.
    public static func plain<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
