import Foundation

public enum TodoLink: Equatable {
    case handoff(UUID)   // unlirice://handoff/<uuid>
    case todo            // unlirice://todo

    /// Strict: scheme `unlirice`; host `handoff` or `todo`; `handoff` has exactly one
    /// path component that parses as a UUID; `todo` has none. No user, password, port,
    /// query or fragment. Anything else → nil (ignored).
    public static func parse(_ url: URL) -> TodoLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.scheme?.lowercased() == "unlirice" else {
            return nil
        }
        guard components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        guard let host = components.host?.lowercased() else {
            return nil
        }

        let nonSlashComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        switch host {
        case "todo":
            guard nonSlashComponents.isEmpty else { return nil }
            return .todo
        case "handoff":
            guard nonSlashComponents.count == 1,
                  let uuid = UUID(uuidString: nonSlashComponents[0]) else {
                return nil
            }
            return .handoff(uuid)
        default:
            return nil
        }
    }

    public var url: URL {
        switch self {
        case .todo:
            return URL(string: "unlirice://todo")!
        case .handoff(let uuid):
            return URL(string: "unlirice://handoff/\(uuid.uuidString)")!
        }
    }
}
