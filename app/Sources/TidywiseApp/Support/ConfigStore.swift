import Foundation

/// Reads and writes the settings – always through the `tidywise` CLI, so that there is exactly one place
/// that knows the file format and validates the values.
enum ConfigStore {
    struct SaveError: Error {
        /// A sentence from the CLI that says what's wrong.
        let message: String
    }

    private static let lock = NSLock()
    private static var cached: (stamp: Date?, config: TidywiseConfig)?

    static var cliInstalled: Bool { Backend.installed }

    private static var fileStamp: Date? {
        (try? FileManager.default.attributesOfItem(atPath: Paths.config.path))?[.modificationDate] as? Date
    }

    /// The current configuration. The CLI is only asked when the file has changed. Synchronous –
    /// call from the background.
    static func load() -> TidywiseConfig {
        let stamp = fileStamp
        lock.lock()
        let hit = cached
        lock.unlock()
        if let hit, hit.stamp == stamp { return hit.config }
        let r = Shell.run(Paths.cli.path, ["config", "--as-json"])
        guard r.ok, let config = decode(r.output) else { return hit?.config ?? TidywiseConfig() }
        remember(config, stamp: stamp)
        return config
    }

    /// The state last read, without starting the CLI (e.g. when quitting the app).
    static var last: TidywiseConfig {
        lock.lock()
        defer { lock.unlock() }
        return cached?.config ?? TidywiseConfig()
    }

    /// Validates and saves. Returns the configuration as the CLI wrote it
    /// (e.g. with the folder names assigned to new topics).
    static func save(_ config: TidywiseConfig) -> Result<TidywiseConfig, SaveError> {
        guard cliInstalled else { return .failure(SaveError(message: "The “tidywise” program isn't installed.")) }
        guard let data = try? JSONEncoder().encode(config), let json = String(data: data, encoding: .utf8) else {
            return .failure(SaveError(message: "The settings couldn't be prepared for saving."))
        }
        let r = Shell.run(Paths.cli.path, ["config", "save", "--json", json, "--as-json"])
        guard r.ok, let saved = decode(r.output) else {
            let text = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(SaveError(message: text.isEmpty ? "Saving failed." : text))
        }
        remember(saved, stamp: fileStamp)
        return .success(saved)
    }

    private static func remember(_ config: TidywiseConfig, stamp: Date?) {
        lock.lock()
        cached = (stamp, config)
        lock.unlock()
    }

    private static func decode(_ output: String) -> TidywiseConfig? {
        // Only the last line is the JSON – Python warnings might come before it.
        guard let line = output.split(separator: "\n").last, let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TidywiseConfig.self, from: data)
    }
}
