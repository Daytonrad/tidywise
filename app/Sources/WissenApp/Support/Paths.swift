import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    /// As with the CLI, state and configuration can be redirected through environment variables – for tests and demo data.
    static let stateDir = env("WISSEN_STATE_DIR") ?? home.appending(path: "Library/Application Support/wissen")
    static let database = stateDir.appending(path: "wissen.sqlite")
    static let status = stateDir.appending(path: "status.json")
    static let config = env("WISSEN_CONFIG") ?? home.appending(path: ".config/wissen/config.toml")
    static let log = home.appending(path: "Library/Logs/wissen/agent.log")
    /// The `wissen` program (see `Backend` for where it lives).
    static var cli: URL { Backend.cli }
    /// The app writes its process id here while it is open – the MCP server only answers while it exists.
    static let appPID = stateDir.appending(path: "app.pid")
    static let serviceLabel = "local.wissen.agent"
    static let plist = home.appending(path: "Library/LaunchAgents/\(serviceLabel).plist")

    private static func env(_ key: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }

    /// The folder as it is named in Finder: “Downloads”, “Desktop” …
    static func folderName(ofFolder path: String) -> String {
        switch path {
        case home.appending(path: "Downloads").path: return "Downloads"
        case home.appending(path: "Documents").path: return "Documents"
        case home.appending(path: "Desktop").path: return "Desktop"
        case home.path: return "Home folder"
        default: return FileManager.default.displayName(atPath: path)
        }
    }

    /// A file's folder as it is named in Finder.
    static func folderName(of filePath: String) -> String {
        folderName(ofFolder: URL(fileURLWithPath: filePath).deletingLastPathComponent().path)
    }

    static func short(_ path: String) -> String {
        path == home.path || path.hasPrefix(home.path + "/") ? "~" + path.dropFirst(home.path.count) : path
    }
}
