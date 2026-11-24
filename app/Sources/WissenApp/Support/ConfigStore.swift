import Foundation

/// Reads and writes the settings – always through the `wissen` CLI, so that there is exactly one place
/// that knows the file format and validates the values.
enum ConfigStore {
    struct SaveError: Error {
        /// A sentence from the CLI that says what's wrong.
        let message: String
    }

    private static let lock = NSLock()
    private static var cached: (stamp: Date?, config: WissenConfig)?

    static var cliInstalled: Bool { Backend.installed }

    private static var fileStamp: Date? {
        (try? FileManager.default.attributesOfItem(atPath: Paths.config.path))?[.modificationDate] as? Date
    }

    /// The current configuration. The CLI is only asked when the file has changed. Synchronous –
    /// call from the background.
    static func load() -> WissenConfig {
        let stamp = fileStamp
        lock.lock()
        let hit = cached
        lock.unlock()
        if let hit, hit.stamp == stamp { return hit.config }
        let r = Shell.run(Paths.cli.path, ["config", "--as-json"])
        guard r.ok, let config = decode(r.output) else { return hit?.config ?? WissenConfig() }
        remember(config, stamp: stamp)
        return config
    }

    /// The state last read, without starting the CLI (e.g. when quitting the app).
    static var last: WissenConfig {
        lock.lock()
        defer { lock.unlock() }
        return cached?.config ?? WissenConfig()
    }

    /// Validates and saves. Returns the configuration as the CLI wrote it
    /// (e.g. with the folder names assigned to new topics).
    static func save(_ config: WissenConfig) -> Result<WissenConfig, SaveError> {
        guard cliInstalled else { return .failure(SaveError(message: "The “wissen” program isn't installed.")) }
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

    private static func remember(_ config: WissenConfig, stamp: Date?) {
        lock.lock()
        cached = (stamp, config)
        lock.unlock()
    }

    private static func decode(_ output: String) -> WissenConfig? {
        // Only the last line is the JSON – Python warnings might come before it.
        guard let line = output.split(separator: "\n").last, let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WissenConfig.self, from: data)
    }
}
