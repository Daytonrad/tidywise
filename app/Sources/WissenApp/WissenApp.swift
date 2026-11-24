import AppKit
import SwiftUI

@main
struct WissenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var state = AppState()

    var body: some Scene {
        Window("Wissen", id: "main") {
            ContentView()
                .environment(state)
                .tint(DS.accent)
                .frame(minWidth: 1000, minHeight: 660)
                .onAppear {
                    if Snapshot.directory != nil { Snapshot.run(state) } else { state.start() }
                }
        }
        .defaultSize(width: 1220, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Check for new files") { state.scan() }.keyboardShortcut("r").disabled(!state.canRunAI || !state.modelInstalled)
                Button(state.aiEnabled ? "Turn AI off" : "Turn AI on") { state.setAIEnabled(!state.aiEnabled) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Open Wissen folder") { state.openRoot() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings …") { state.page = .settings }.keyboardShortcut(",").disabled(state.showSetup)
            }
            CommandGroup(before: .sidebar) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.rawValue) { state.page = page }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                        .disabled(state.showSetup)
                }
                Divider()
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(state)
                .tint(DS.accent)
                .onAppear { state.start() }
        } label: {
            MenuBarLabel().environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: !state.aiEnabled ? "moon.zzz" : (state.isBusy ? "brain.filled.head.profile" : "brain.head.profile"))
            if state.isWorking, let tps = state.lastCall?.tokensPerSecond {
                Text("\(Int(tps)) tok/s").monospacedDigit()
            } else if state.reviewCount > 0 {
                Text("\(state.reviewCount)").monospacedDigit()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        guard Snapshot.directory == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        // The MCP server for AI assistants only answers while this file points at a running app.
        try? FileManager.default.createDirectory(at: Paths.stateDir, withIntermediateDirectories: true)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: Paths.appPID, atomically: true, encoding: .utf8)
    }

    // App closed → nothing keeps running: stop the current run, unload the model from memory.
    func applicationWillTerminate(_ notification: Notification) {
        guard Snapshot.directory == nil else { return }
        try? FileManager.default.removeItem(at: Paths.appPID)
        AppState.stopRunsAndUnload(timeout: 3)
    }

    // Window closed → the app keeps running in the menu bar
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Main window

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.showSetup {
                SetupView()
            } else {
                main
            }
        }
        .overlay(alignment: .bottom) { Toast() }
    }

    private var main: some View {
        NavigationSplitView {
            List {
                Section {
                    row(.home)
                    row(.review)
                    row(.files)
                    if state.config.linksEnabled || !state.links.isEmpty { row(.links) }
                }
                Section("In the background") {
                    row(.system)
                    row(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarStatus().padding(10) }
        } detail: {
            Group {
                switch state.page {
                case .home: HomeView()
                case .review: ReviewView()
                case .files: FilesView()
                case .links: LinksView()
                case .system: SystemView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.page)
            .pageTitle(state.page.rawValue)
            .toolbar {
                if let cmd = state.runningCommand {
                    ToolbarItem(placement: .status) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("\(cmd) …").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Spacer()
                    AIToggle()
                    Button { state.openRoot() } label: { Label("Open folder", systemImage: "folder") }
                        .labelStyle(.titleAndIcon)
                        .help("Open the folder with all sorted files in Finder (⇧⌘O)")
                    Button { state.scan() } label: { Label("Check for new files", systemImage: "arrow.clockwise") }
                        .labelStyle(.titleAndIcon)
                        .help("Check \(state.config.watchNames) for loose files now (⌘R)")
                        .disabled(!state.canRunAI || !state.modelInstalled)
                }
            }
        }
    }

    /// Custom rows instead of the system selection: a subtle highlight in the accent color, counter in orange.
    private func row(_ p: Page) -> some View {
        let selected = state.page == p
        return Button { state.page = p } label: {
            HStack(spacing: 9) {
                Image(systemName: p.icon)
                    .symbolVariant(selected ? .fill : .none)
                    .foregroundStyle(selected ? AnyShapeStyle(DS.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 22)
                Text(p.rawValue).fontWeight(selected ? .semibold : .regular)
                Spacer(minLength: 4)
                if p == .review, state.reviewCount > 0 {
                    Text("\(state.reviewCount)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(DS.attention, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(selected ? DS.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        .listRowSeparator(.hidden)
    }
}

/// The state in one sentence – always visible; one click takes you to where you can do something about it.
struct SidebarStatus: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            switch state.health {
            case .needsReview: state.page = .review
            case .noModel, .offline: state.openSettings(.model)
            case .noService: state.openSettings(.general)
            default: state.page = .system
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    StatusDot(color: state.healthColor, pulsing: state.health == .working)
                    Text(state.healthTitle).font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                if state.health == .working {
                    ProgressBar(value: state.activity?.isAlive == true ? state.activity?.progress : nil, height: 4)
                }
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(state.health == .needsReview ? "Go to the suggestions" : "Show what's running in the background")
    }

    private var detail: String {
        switch state.health {
        case .starting: return "Loading data"
        case .setup: return "A few steps to go"
        case .paused: return state.stopping ? "Stopping …" : "Uses no memory"
        case .offline: return "Ollama isn't running"
        case .noModel: return state.download.map { $0.failed ? "Download failed" : $0.detail } ?? "Download it once"
        case .working:
            if let a = state.activity, a.isAlive {
                if let d = a.done, let t = a.total { return "\(d.formatted(Format.integer)) of \(t.formatted(Format.integer))" }
                return a.label ?? a.task ?? "working"
            }
            return state.runningCommand ?? "working"
        case .needsReview: return "A quick look is enough"
        case .noService: return "Sorts only when you ask"
        case .ok: return "Next check \(state.nextRunText)"
        }
    }
}

/// Feedback after an action: short and clear, the terminal output only on request.
struct Toast: View {
    @Environment(AppState.self) private var state
    @ViewState private var expanded = false

    var body: some View {
        ZStack {
            if let r = state.result {
                content(r)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: r) {
                        expanded = false
                        guard !r.failed else { return }
                        try? await Task.sleep(for: .seconds(6))
                        if !Task.isCancelled, !expanded, state.result == r { state.result = nil }
                    }
            }
        }
        .animation(.snappy, value: state.result)
    }

    private func content(_ r: CommandResult) -> some View {
        let hasDetails = r.output.contains("\n")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: r.failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(r.failed ? DS.attention : DS.ok)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.failed ? "That didn't work" : r.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(r.summary ?? (r.failed ? r.title : "Done"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                if hasDetails {
                    Button(expanded ? "Less" : "Details") { expanded.toggle() }.buttonStyle(.link).font(.callout)
                }
                Button { state.result = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Close")
            }
            if expanded {
                ScrollView {
                    Text(r.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .well()
            }
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DS.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .padding(20)
    }
}

/// The “AI on/off” switch – top right in the window. Off stops running work and frees the memory right away.
struct AIToggle: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Toggle(isOn: Binding(get: { state.aiEnabled }, set: { state.setAIEnabled($0) })) {
            Text("AI")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(state.stopping)
        .help(state.aiEnabled
              ? "Turn AI off: stop running work and free the memory right away (⇧⌘K)"
              : "Turn AI on: Wissen sorts again \(state.intervalText) (⇧⌘K)")
    }
}
