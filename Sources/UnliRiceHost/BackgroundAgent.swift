import Foundation
import ServiceManagement

public enum BackgroundAgentError: Error, CustomStringConvertible {
    case binaryNotFound
    case launchctlFailed(String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "Background work needs the packaged app. Run Scripts/make-app.sh and open Unli Rice.app."
        case .launchctlFailed(let detail):
            return "Background service registration failed: \(detail)"
        }
    }
}

/// Installing and removing the background launch agent using SMAppService.
public enum BackgroundAgent {
    public static let label = "com.calmdownoscar.unlirice.agent"
    public static let interval = 300

    private static var service: SMAppService {
        SMAppService.agent(plistName: "com.calmdownoscar.unlirice.agent.plist")
    }

    public static func plistURL(executable: URL? = Bundle.main.executableURL) -> URL {
        guard let executable else {
            return URL(fileURLWithPath: "/Applications/Unli Rice.app/Contents/Library/LaunchAgents/\(label).plist")
        }
        return executable
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    public static func isInstalled() -> Bool {
        let status = service.status
        return status == .enabled || status == .requiresApproval
    }

    /// Where the agent binary is, given where this process is running from.
    public static func locateBinary(
        near executable: URL? = Bundle.main.executableURL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let executable else { return nil }
        let candidate = executable.deletingLastPathComponent().appendingPathComponent("unlirice-agent")
        return fileManager.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    /// Registers the LaunchAgent with the system via SMAppService.
    public static func install(logDirectory: URL? = nil) throws {
        guard locateBinary() != nil else { throw BackgroundAgentError.binaryNotFound }
        do {
            try service.register()
        } catch {
            throw BackgroundAgentError.launchctlFailed("\(error)")
        }
    }

    /// Unregisters the LaunchAgent from the system.
    public static func uninstall() throws {
        do {
            try service.unregister()
        } catch {
            throw BackgroundAgentError.launchctlFailed("\(error)")
        }
    }
}
