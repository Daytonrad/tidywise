import AppKit
import Foundation

/// Ollama is the program that runs the AI model locally. This is how Wissen finds and starts it.
enum OllamaSetup {
    static let downloadPage = URL(string: "https://ollama.com/download")!

    private static func firstExisting(_ paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    static var appPath: String? {
        firstExisting(["/Applications/Ollama.app", Paths.home.appending(path: "Applications/Ollama.app").path])
    }

    static var cliPath: String? { firstExisting(["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]) }
    static var brewPath: String? { firstExisting(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) }
    static var isInstalled: Bool { appPath != nil || cliPath != nil }

    /// Starts Ollama the way it was installed. Synchronous – call from the background.
    @discardableResult
    static func start() -> Shell.Result {
        if let appPath {
            return Shell.run("/usr/bin/open", ["-g", "-a", appPath])
        }
        if let brewPath, let cliPath, cliPath.hasPrefix((brewPath as NSString).deletingLastPathComponent) {
            return Shell.run(brewPath, ["services", "start", "ollama"])
        }
        if let cliPath {  // without the Homebrew service: start the server directly; it keeps running independently of Wissen
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                return Shell.Result(status: 0, output: "")
            } catch {
                return Shell.Result(status: -1, output: error.localizedDescription)
            }
        }
        return Shell.Result(status: -1, output: "Ollama isn't installed.")
    }

    /// Installs Ollama through Homebrew and starts it. Takes one to two minutes.
    static func installWithBrew() -> Shell.Result {
        guard let brewPath else { return Shell.Result(status: -1, output: "Homebrew isn't installed.") }
        let install = Shell.run(brewPath, ["install", "ollama"])
        guard install.ok else { return install }
        return Shell.run(brewPath, ["services", "start", "ollama"])
    }
}
