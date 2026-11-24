import AppKit
import Foundation

/// The setup steps, in this order.
enum SetupStep: Int, CaseIterable, Identifiable {
    case welcome, model, folders, topics, automation
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .model: "AI model"
        case .folders: "Folders"
        case .topics: "Topics"
        case .automation: "Automation"
        }
    }
}

/// Everything that changes settings or sets something up: saving the configuration, the background service,
/// starting Ollama, downloading a model.
extension AppState {
    // MARK: Saving settings

    /// Changes the settings and saves right away. The interface shows the new value immediately;
    /// if the CLI rejects it, the interface jumps back and says why.
    func updateConfig(_ change: (inout WissenConfig) -> Void) {
        var next = config
        change(&next)
        saveConfig(next)
    }

    func saveConfig(_ next: WissenConfig, then: (@MainActor (Bool) -> Void)? = nil) {
        guard next != config || then != nil else { return }
        let before = config
        config = next
        TopicStyle.register(next.topics)
        pendingSaves += 1
        // Save one after another, so that with quick changes the latest state wins.
        saveChain = Task { [previous = saveChain] in
            await previous?.value
            let result = await Task.detached { ConfigStore.save(next) }.value
            pendingSaves -= 1
            switch result {
            case .success(let saved):
                if pendingSaves == 0 { apply(saved) }
                then?(true)
            case .failure(let error):
                if pendingSaves == 0 { apply(before) }
                self.result = CommandResult(title: "Save setting", output: error.message, failed: true)
                then?(false)
            }
        }
    }

    // MARK: Choosing a folder

    /// Asks for a folder using the system dialog.
    func chooseFolder(title: String, startingAt path: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = title
        if let path { panel.directoryURL = URL(fileURLWithPath: path) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    // MARK: Background service

    func installService() {
        guard runningCommand == nil else { return }
        runningCommand = "Set up automation"
        Task {
            let r = await Shell.runAsync(Paths.cli.path, ["service", "install"])
            await refreshData()
            runningCommand = nil
            result = r.ok
                ? CommandResult(title: "Automation set up", output: "Wissen now checks \(intervalText) while the app is open.", failed: false)
                : CommandResult(title: "Set up automation", output: r.output.trimmingCharacters(in: .whitespacesAndNewlines), failed: true)
        }
    }

    func removeService() {
        guard runningCommand == nil else { return }
        runningCommand = "Remove automation"
        Task {
            _ = await Shell.runAsync(Paths.cli.path, ["service", "uninstall"])
            await refreshData()
            runningCommand = nil
        }
    }

    // MARK: Ollama

    func startOllama() {
        guard ollamaBusy == nil else { return }
        ollamaBusy = "Starting Ollama …"
        Task {
            let r = await Task.detached { OllamaSetup.start() }.value
            await waitForOllama(seconds: r.ok ? 15 : 0)
            ollamaBusy = nil
            if !ollamaUp {
                result = CommandResult(title: "Start Ollama", output: r.ok ? "Ollama isn't responding yet. Try again in a moment." : r.output, failed: true)
            }
        }
    }

    func installOllamaWithBrew() {
        guard ollamaBusy == nil else { return }
        ollamaBusy = "Installing Ollama – this takes a minute or two …"
        Task {
            let r = await Task.detached { OllamaSetup.installWithBrew() }.value
            await waitForOllama(seconds: r.ok ? 20 : 0)
            ollamaBusy = nil
            if !r.ok {
                result = CommandResult(title: "Install Ollama", output: r.output.trimmingCharacters(in: .whitespacesAndNewlines), failed: true)
            }
        }
    }

    func openOllamaDownloadPage() { NSWorkspace.shared.open(OllamaSetup.downloadPage) }

    private func waitForOllama(seconds: Int) async {
        for _ in 0..<max(1, seconds * 2) {
            await refreshLive()
            if ollamaUp { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: Downloading a model

    /// Downloads a model through Ollama. `select` then makes it the active model.
    func downloadModel(_ tag: String, select: Bool = true) {
        let tag = tag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, downloadTask == nil else { return }
        download = ModelDownload(model: tag)
        let ollama = Ollama(baseURL: config.ollamaURL)
        downloadTask = Task {
            var layers: [String: (total: Int64, completed: Int64)] = [:]
            do {
                for try await event in ollama.pull(model: tag) {
                    if let error = event.error { throw PullFailure(message: error) }
                    if let digest = event.digest, let total = event.total {
                        layers[digest] = (total, event.completed ?? 0)
                        download?.total = layers.values.reduce(0) { $0 + $1.total }
                        download?.completed = layers.values.reduce(0) { $0 + $1.completed }
                    }
                    if let status = event.status { download?.status = Self.pullStatus(status) }
                }
                await refreshLive()
                guard isInstalled(tag) else { throw PullFailure(message: "Ollama finished the download, but the model is still missing.") }
                download = nil
                downloadTask = nil
                if select, config.model != tag { updateConfig { $0.model = tag } }
                result = CommandResult(title: "Model downloaded", output: "\(tag) is ready.", failed: false)
            } catch is CancellationError {
                download = nil
                downloadTask = nil
            } catch {
                downloadTask = nil
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    download = nil
                } else {
                    download?.error = Self.pullError(error)
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        download = nil
    }

    private struct PullFailure: Error { let message: String }

    private static func pullStatus(_ status: String) -> String {
        if status.hasPrefix("pulling manifest") { return "Looking for the model …" }
        if status.hasPrefix("pulling") { return "Downloading …" }
        if status.hasPrefix("verifying") { return "Verifying the download …" }
        if status.hasPrefix("writing") || status.hasPrefix("removing") { return "Cleaning up …" }
        if status == "success" { return "Done" }
        return status
    }

    private static func pullError(_ error: Error) -> String {
        if let failure = error as? PullFailure {
            if failure.message.contains("not found") || failure.message.contains("does not exist") {
                return "Ollama doesn't have this model. Check the name."
            }
            return failure.message
        }
        if (error as? URLError) != nil { return "The connection to Ollama was lost. The download picks up where it left off the next time you try." }
        return error.localizedDescription
    }

    // MARK: AI assistants (MCP)

    func refreshAssistants() async {
        guard cliInstalled else { return }
        if let status = await Task.detached(operation: { Sources.assistants() }).value { assistants = status }
    }

    /// Registers the MCP server with an assistant through that assistant's own command line.
    func connectAssistant(_ client: AssistantsStatus.Client) {
        changeAssistant(client, action: "add", busy: "Connecting \(client.title) …",
                        done: "\(client.title) can now search your archive. Start a new session there to use it.")
    }

    func disconnectAssistant(_ client: AssistantsStatus.Client) {
        changeAssistant(client, action: "remove", busy: "Removing from \(client.title) …", done: "Removed from \(client.title).")
    }

    private func changeAssistant(_ client: AssistantsStatus.Client, action: String, busy: String, done: String) {
        guard assistantBusy == nil else { return }
        assistantBusy = client.id
        Task {
            let r = await Shell.runAsync(Paths.cli.path, ["mcp", action, client.id, "--as-json"])
            if let status = Sources.decodeAssistants(r) { assistants = status }
            await refreshData()  // connecting switches “let assistants search” on
            assistantBusy = nil
            result = r.ok
                ? CommandResult(title: client.title, output: done, failed: false)
                : CommandResult(title: client.title, output: r.output.trimmingCharacters(in: .whitespacesAndNewlines), failed: true)
        }
    }

    // MARK: Setup

    func beginSetup() {
        setupStep = .welcome
        setupRequested = true
    }

    /// Finishes setup: save the settings, set up automation if wanted, check once.
    func finishSetup(_ draft: WissenConfig, automation: Bool) {
        saveConfig(draft) { [self] ok in
            guard ok else { return }
            setupRequested = false
            page = .home
            Task {
                if automation, !service.loaded {
                    _ = await Shell.runAsync(Paths.cli.path, ["service", "install"])
                } else if !automation, service.loaded {
                    _ = await Shell.runAsync(Paths.cli.path, ["service", "uninstall"])
                }
                await refreshAll()
                if ollamaUp, modelInstalled { scan() }
            }
        }
    }
}
