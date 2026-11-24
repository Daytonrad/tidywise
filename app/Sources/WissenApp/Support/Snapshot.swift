import AppKit
import SwiftUI

/// Developer aid: `Wissen --snapshot <folder>` renders every page (light and dark, including special states)
/// as a PNG and quits. That way the interface can be checked without screen recording permission.
@MainActor
enum Snapshot {
    static let directory: URL? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }()

    static func run(_ state: AppState) {
        guard let directory else { return }
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            await state.refreshAll()
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.styleMask.contains(.titled) }) else {
                NSApp.terminate(nil)
                return
            }
            let real = (state.files, state.activity, state.ollamaUp, state.service)

            // `--snapshot <folder> Files Links` renders only the named pages (light) – for quick experiments.
            // “Setup” and the settings sections (“Folders”, “Topics” …) can be named the same way.
            let args = Set(CommandLine.arguments.dropFirst())
            let only = Page.allCases.filter { args.contains($0.rawValue) }
            let onlyTabs = SettingsTab.allCases.filter { args.contains($0.rawValue) }
            if !only.isEmpty || !onlyTabs.isEmpty || args.contains("Setup") {
                window.setContentSize(NSSize(width: 1220, height: 800))
                for page in only {
                    state.page = page
                    await shoot(window, directory, page.rawValue.lowercased())
                }
                window.setContentSize(NSSize(width: 1220, height: 1100))
                for tab in onlyTabs { await shootSettings(state, tab, window, directory, "") }
                if args.contains("Setup") { await shootSetup(state, window, directory, "") }
                NSApp.terminate(nil)
                return
            }

            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let suffix = dark ? "-dark" : ""
                window.setContentSize(NSSize(width: 1220, height: 800))

                state.selectedFileID = state.moved.first?.id
                for page in Page.allCases {
                    state.page = page
                    await shoot(window, directory, "\(page.rawValue.lowercased())\(suffix)")
                }

                // Show long pages in full
                window.setContentSize(NSSize(width: 1220, height: 1700))
                for page in [Page.home, .system] {
                    state.page = page
                    await shoot(window, directory, "\(page.rawValue.lowercased())-long\(suffix)")
                }
                window.setContentSize(NSSize(width: 1220, height: 800))

                // Special states of the Home page
                state.page = .home
                state.activity = Activity(busy: true, pid: Int(getpid()), task: "Sorting files",
                                          label: "Invoice_utilities_2026.pdf", done: 12, total: 40,
                                          started_at: ISO8601DateFormatter().string(from: .now.addingTimeInterval(-95)))
                await shoot(window, directory, "home-working\(suffix)")
                state.activity = real.1

                state.ollamaUp = false
                await shoot(window, directory, "home-offline\(suffix)")
                state.ollamaUp = real.2

                state.files = real.0.filter { $0.status == "moved" && !$0.isInInbox }
                await shoot(window, directory, "home-tidy\(suffix)")
                state.page = .review
                await shoot(window, directory, "review-empty\(suffix)")
                state.files = real.0

                state.result = CommandResult(title: "Move suggestions",
                                             output: "  ~/Downloads/a.pdf  →  ~/Downloads/Wissen/Topics/study/a.pdf\n2 file(s) moved. Undo: wissen undo --last 2",
                                             failed: false)
                await shoot(window, directory, "review-feedback\(suffix)")
                state.result = nil

                // Model still missing / being downloaded
                state.page = .home
                let installed = state.installedModels
                state.installedModels = []
                await shoot(window, directory, "home-no-model\(suffix)")
                state.download = ModelDownload(model: state.config.model, status: "Downloading …", completed: 2_400_000_000, total: 6_100_000_000)
                await shoot(window, directory, "home-model-loading\(suffix)")
                state.page = .settings
                state.settingsTab = .model
                await shoot(window, directory, "settings-model-loading\(suffix)")
                state.download = nil
                state.installedModels = installed

                window.setContentSize(NSSize(width: 1220, height: 1100))
                for tab in SettingsTab.allCases { await shootSettings(state, tab, window, directory, suffix) }
                await shootSetup(state, window, directory, suffix)
                window.setContentSize(NSSize(width: 1220, height: 800))
                state.page = .home

                await shootMenuBar(state, directory, "menu\(suffix)", dark: dark)
            }
            NSApp.terminate(nil)
        }
    }

    private static func shootSettings(_ state: AppState, _ tab: SettingsTab, _ window: NSWindow, _ directory: URL, _ suffix: String) async {
        state.page = .settings
        state.settingsTab = tab
        await shoot(window, directory, "settings-\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))\(suffix)")
    }

    private static func shootSetup(_ state: AppState, _ window: NSWindow, _ directory: URL, _ suffix: String) async {
        state.setupRequested = true
        for step in SetupStep.allCases {
            state.setupStep = step
            await shoot(window, directory, "setup-\(step.rawValue + 1)-\(step.title.lowercased().replacingOccurrences(of: " ", with: "-"))\(suffix)")
        }
        state.setupRequested = false
    }

    private static func shoot(_ window: NSWindow, _ directory: URL, _ name: String) async {
        try? await Task.sleep(for: .milliseconds(900))
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        write(view, directory, name)
    }

    private static func shootMenuBar(_ state: AppState, _ directory: URL, _ name: String, dark: Bool) async {
        let host = NSHostingView(rootView: MenuBarView().environment(state).tint(DS.accent).background(DS.page))
        let size = host.fittingSize
        let panel = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.contentView = host
        panel.orderBack(nil)
        try? await Task.sleep(for: .milliseconds(500))
        write(host, directory, name)
        panel.close()
    }

    private static func write(_ view: NSView, _ directory: URL, _ name: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appending(path: "\(name).png"))
    }
}
