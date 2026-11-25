import Foundation

/// Where the program that does the actual work (`tidywise`, written in Python) lives. There are two layouts:
///
/// - **Downloaded app:** the Python sources sit inside the app. The app looks for a Python on this Mac and
///   writes a small launcher script that everything else calls – the app itself, the background service
///   and AI assistants.
/// - **Built from source** (`./install.sh`): `~/.local/bin/tidywise` points into the project's Python environment.
enum Backend {
    /// The Python sources inside the app bundle, if this is a downloaded build.
    static let bundledSources: URL? = {
        guard let dir = Bundle.main.resourceURL?.appending(path: "python"),
              FileManager.default.fileExists(atPath: dir.appending(path: "tidywise/__main__.py").path) else { return nil }
        return dir
    }()

    static var isBundled: Bool { bundledSources != nil }

    /// The launcher the downloaded app writes. Its path stays the same even when the app is moved or updated.
    static let launcher = Paths.stateDir.appending(path: "bin/tidywise")

    /// The `tidywise` program to call.
    static var cli: URL { isBundled ? launcher : Paths.home.appending(path: ".local/bin/tidywise") }

    static var installed: Bool { FileManager.default.isExecutableFile(atPath: cli.path) }

    /// Places a Python could be. `/usr/bin/python3` is left out on purpose: on a Mac without developer tools it
    /// only opens an install dialog, and where it exists it is too old.
    private static var pythonCandidates: [String] {
        let folders = ["/opt/homebrew/bin", "/usr/local/bin", "/Library/Frameworks/Python.framework/Versions/Current/bin",
                       Paths.home.appending(path: ".local/bin").path]
        let names = ["python3", "python3.15", "python3.14", "python3.13", "python3.12"]
        return folders.flatMap { folder in names.map { "\(folder)/\($0)" } }
    }

    /// A Python that is new enough (3.12+), or nil. Synchronous – call from the background.
    static func findPython() -> String? {
        pythonCandidates.first { path in
            FileManager.default.isExecutableFile(atPath: path)
                && Shell.run(path, ["-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)"]).ok
        }
    }

    /// Downloaded app only: writes the launcher if it is missing or out of date (app moved, Python updated).
    /// Returns the chosen Python path (or nil if Python 3.12+ is missing). Synchronous – call from the background.
    @discardableResult
    static func prepare() -> String? {
        guard let sources = bundledSources, let python = findPython() else { return nil }
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/sh
        # Written by Tidywise.app – starts the part of Tidywise that reads and moves files.
        # Rewritten automatically when the app moves or Python changes; edits here do not last.
        export PYTHONPATH=\(quoted(sources.path))
        export PYTHONPYCACHEPREFIX=\(quoted(Paths.stateDir.appending(path: "pycache").path))
        export TIDYWISE_CLI=\(quoted(launcher.path))
        exec \(quoted(python)) -m tidywise "$@"

        """
        if (try? String(contentsOf: launcher, encoding: .utf8)) == script, installed { return python }
        do {
            try FileManager.default.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
            try script.write(to: launcher, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
            return python
        } catch {
            return nil
        }
    }

    /// The background service remembers where the Python sources and interpreter are. If the downloaded app
    /// moved or Python was updated since the service was set up, it has to be set up again.
    /// Never touches a service that was set up from source.
    /// Sets the service up again when `serviceNeedsUpdate` says so – at most once per app start for the same
    /// sources and Python, so a mismatch that `service install` can't fix doesn't restart launchd every few seconds.
    static func refreshServiceIfNeeded(python: String) {
        guard let sources = bundledSources else { return }
        let key = sources.path + "\n" + python
        refreshLock.lock()
        defer { refreshLock.unlock() }
        guard refreshedFor != key, serviceNeedsUpdate(python: python) else { return }
        refreshedFor = key
        _ = Shell.run(cli.path, ["service", "install"])
    }
    private static let refreshLock = NSLock()
    nonisolated(unsafe) private static var refreshedFor: String?

    static func serviceNeedsUpdate(python: String) -> Bool {
        guard let sources = bundledSources,
              ProcessInfo.processInfo.environment["TIDYWISE_STATE_DIR"] == nil,
              let data = try? Data(contentsOf: Paths.plist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let env = plist["EnvironmentVariables"] as? [String: String],
              let recorded = env["PYTHONPATH"] else { return false }
        if recorded != sources.path { return true }
        guard let args = plist["ProgramArguments"] as? [String], let recordedPython = args.first else { return true }
        if !FileManager.default.isExecutableFile(atPath: recordedPython) { return true }
        let a = URL(fileURLWithPath: recordedPython).resolvingSymlinksInPath().path
        let b = URL(fileURLWithPath: python).resolvingSymlinksInPath().path
        return a != b
    }
}
