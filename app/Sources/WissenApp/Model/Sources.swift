import Darwin
import Foundation

/// Reads the individual data sources. Everything here is synchronous and runs in the background.
enum Sources {
    struct DBSnapshot {
        var files: [FileItem] = []
        var links: [LinkItem] = []
        var searches: [SearchItem] = []
        var calls: [LLMCall] = []
        var meta: [String: String] = [:]
    }

    static func readDatabase() -> DBSnapshot {
        guard let db = Database(url: Paths.database) else { return DBSnapshot() }
        var s = DBSnapshot()
        s.files = db.query("SELECT * FROM files WHERE status IN ('planned','moved') ORDER BY id DESC").map { r in
            FileItem(
                id: r.int("id") ?? 0,
                name: r.string("name") ?? "?",
                topic: r.string("topic"),
                newTopic: r.string("new_topic"),
                status: r.string("status") ?? "",
                summary: r.string("summary") ?? "",
                keywords: r.string("keywords") ?? "",
                sourceURL: r.string("source_url"),
                confidence: r.double("confidence") ?? 0,
                origPath: r.string("orig_path") ?? "",
                curPath: r.string("cur_path"),
                movedAt: Format.date(r.string("moved_at")),
                classifiedAt: Format.date(r.string("classified_at"))
            )
        }
        s.links = db.query("SELECT * FROM links ORDER BY last_visit DESC LIMIT 5000").map { r in
            LinkItem(url: r.string("url") ?? "", title: r.string("title") ?? "", domain: r.string("domain") ?? "",
                     topic: r.string("topic"), lastVisit: Format.date(r.string("last_visit")), visits: r.int("visits") ?? 1)
        }
        s.searches = db.query("SELECT * FROM searches ORDER BY at DESC LIMIT 300").map { r in
            SearchItem(term: r.string("term") ?? "", at: Format.date(r.string("at")))
        }
        s.calls = db.query("SELECT * FROM llm_calls ORDER BY id DESC LIMIT 500").compactMap { r in
            guard let at = Format.date(r.string("at")) else { return nil }
            return LLMCall(
                id: r.int("id") ?? 0, at: at, model: r.string("model") ?? "", kind: r.string("kind") ?? "",
                label: r.string("label") ?? "", promptTokens: r.int("prompt_tokens") ?? 0,
                outputTokens: r.int("output_tokens") ?? 0, promptMs: r.double("prompt_ms") ?? 0,
                evalMs: r.double("eval_ms") ?? 0, loadMs: r.double("load_ms") ?? 0, totalMs: r.double("total_ms") ?? 0,
                images: r.int("images") ?? 0, ok: (r.int("ok") ?? 1) == 1, error: r.string("error")
            )
        }
        for r in db.query("SELECT key, value FROM meta") {
            if let k = r.string("key") { s.meta[k] = r.string("value") }
        }
        return s
    }

    static func readActivity() -> Activity? {
        guard let data = try? Data(contentsOf: Paths.status) else { return nil }
        return try? JSONDecoder().decode(Activity.self, from: data)
    }

    static func ollamaProcesses() -> [ProcessStat] {
        let out = Shell.run("/bin/ps", ["-axo", "pid=,rss=,%cpu=,command="]).output
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4 else { return nil }
            let cmd = String(parts[3])
            guard cmd.contains("ollama"), !cmd.contains("ps -axo") else { return nil }
            guard let pid = Int(parts[0]), let rss = Int64(parts[1]),
                  let cpu = Double(parts[2].replacingOccurrences(of: ",", with: ".")) else { return nil }
            let exe = cmd.split(separator: " ").first.map(String.init) ?? cmd
            return ProcessStat(pid: pid, rssBytes: rss * 1024, cpu: cpu, command: exe.hasSuffix("ollama") ? cmd : exe)
        }
        .sorted { $0.rssBytes > $1.rssBytes }
    }

    /// Memory used, as in Activity Monitor: app memory + wired + compressed.
    static func systemMemory() -> (used: Int64, total: Int64) {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = Int64(vm_kernel_page_size)
        let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return (used, total)
    }

    static func serviceStatus() -> ServiceStatus {
        let r = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(Paths.serviceLabel)"])
        guard r.ok else { return ServiceStatus() }
        var s = ServiceStatus(loaded: true)
        for raw in r.output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("state = ") && s.runs == nil { s.running = line.hasSuffix("running") && !line.hasSuffix("not running") }
            if line.hasPrefix("runs = ") { s.runs = Int(line.dropFirst(7)) }
            if line.hasPrefix("last exit code = ") { s.lastExit = String(line.dropFirst(17)) }
        }
        return s
    }

    /// The Python program behind `wissen` – the one that needs Full Disk Access.
    static func helperPath() -> String? {
        struct Status: Decodable { let python: String }
        let r = Shell.run(Paths.cli.path, ["service", "status"])
        guard r.ok, let line = r.output.split(separator: "\n").last, let data = line.data(using: .utf8) else { return nil }
        return (try? JSONDecoder().decode(Status.self, from: data))?.python
    }

    static func assistants() -> AssistantsStatus? {
        decodeAssistants(Shell.run(Paths.cli.path, ["mcp", "status", "--as-json"]))
    }

    static func decodeAssistants(_ r: Shell.Result) -> AssistantsStatus? {
        guard r.ok, let line = r.output.split(separator: "\n").last, let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AssistantsStatus.self, from: data)
    }

    static func logTail(lines: Int = 300) -> String {
        guard let text = try? String(contentsOf: Paths.log, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }
}
