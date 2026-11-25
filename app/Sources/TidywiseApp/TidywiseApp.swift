import AppKit
import SwiftUI

@main
struct TidywiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var state = AppState()

    var body: some Scene {
        Window("Tidywise", id: "main") {
            ContentView()
                .environment(state)
                .tint(DS.accent)
                .frame(minWidth: 1000, minHeight: 660)
                .background(MainWindowAccessor())
                .onAppear {
                    if Snapshot.directory != nil { Snapshot.run(state) } else { state.start() }
                }
        }
        .defaultSize(width: 1220, height: 800)
        .menuBarAppLaunch()
        .commands {
            CommandGroup(replacing: .windowSize) {
                Button("Minimize to Menu Bar") { MainWindow.hide() }.keyboardShortcut("m")
            }
            CommandGroup(after: .newItem) {
                Button("Check for new files") { state.scan() }.keyboardShortcut("r").disabled(!state.canScan)
                Button(state.aiEnabled ? "Turn AI off" : "Turn AI on") { state.setAIEnabled(!state.aiEnabled) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Open Tidywise folder") { state.openRoot() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings …") { state.page = .settings }.keyboardShortcut(",").disabled(state.showSetup)
            }
            CommandGroup(before: .sidebar) {
                let visiblePages = Page.allCases.filter { $0 != .links || state.config.linksEnabled || !state.links.isEmpty }
                ForEach(Array(visiblePages.enumerated()), id: \.element) { index, page in
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: !state.aiEnabled ? "moon.zzz" : (state.isBusy ? "brain.filled.head.profile" : "brain.head.profile"))
            if state.isWorking, let tps = state.lastCall?.tokensPerSecond {
                Text("\(Int(tps)) tok/s").monospacedDigit()
            } else if state.reviewCount > 0 {
                Text("\(state.reviewCount)").monospacedDigit()
            }
        }
        // The icon is there from launch on – even when the main window stays closed.
        .onAppear {
            MainWindow.open = { openWindow(id: "main") }
            if Snapshot.directory != nil { openWindow(id: "main") } else { state.start() }
        }
        .onChange(of: state.showSetup) { _, setup in
            if setup { MainWindow.show() }  // first start: setup needs the window
        }
    }
}

extension Scene {
    /// Tidywise lives in the menu bar: the main window only opens by itself when setup is needed (see MenuBarLabel).
    /// macOS 14 can't hold it back – there it opens at launch as before and can be put away right after.
    func menuBarAppLaunch() -> some Scene {
        if #available(macOS 15, *) {
            return defaultLaunchBehavior(.suppressed)
        } else {
            return self
        }
    }
}

/// The main window comes and goes, the app stays in the menu bar (no Dock icon, see LSUIElement in build.sh).
@MainActor
enum MainWindow {
    fileprivate static weak var window: NSWindow?
    /// Put away with the yellow button / ⌘M: still there, just not on screen.
    private static var hidden = false
    /// SwiftUI's `openWindow`, handed over by a view that has it (the menu bar icon).
    static var open: (() -> Void)?

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if hidden, let window {
            hidden = false
            window.makeKeyAndOrderFront(nil)
        } else {
            hidden = false
            open?()
        }
    }

    static func hide() {
        guard let window, window.isVisible else { return }
        hidden = true
        window.orderOut(nil)
        NSApp.deactivate()  // hand the keyboard back to the app that was in front before
    }

    fileprivate static func attach(_ window: NSWindow?) {
        guard let window, window !== self.window else { return }
        self.window = window
        hidden = false
        // The yellow button puts the window away into the menu bar instead of the Dock (there is no Dock icon).
        if let button = window.standardWindowButton(.miniaturizeButton) {
            button.target = MinimizeTarget.shared
            button.action = #selector(MinimizeTarget.minimize(_:))
        }
    }
}

private final class MinimizeTarget: NSObject {
    static let shared = MinimizeTarget()
    @MainActor @objc func minimize(_ sender: Any?) { MainWindow.hide() }
}

/// Finds the NSWindow behind the SwiftUI main window.
private struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { MainWindow.attach(view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { MainWindow.attach(view.window) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Snapshot.directory == nil else {
            NSApp.setActivationPolicy(.regular)  // screenshots need a normal window in front
            return
        }
        NSApp.setActivationPolicy(.accessory)  // menu bar only – no Dock icon, not in ⌘Tab
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

    // Opened again from Finder, Spotlight or Launchpad while it is running → show the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.show()
        return false
    }
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
                    AIToggle().controlSize(.small)
                    Button { state.openRoot() } label: { Label("Open folder", systemImage: "folder") }
                        .labelStyle(.titleAndIcon)
                        .help("Open the folder with all sorted files in Finder (⇧⌘O)")
                    Button { state.scan() } label: { Label("Check for new files", systemImage: "arrow.clockwise") }
                        .labelStyle(.titleAndIcon)
                        .help("Check \(state.config.watchNames) for loose files now (⌘R)")
                        .disabled(!state.canScan)
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
        HStack(spacing: 5) {
            Text("AI")
                .font(.callout.weight(.medium))
                .foregroundStyle(state.aiEnabled ? .primary : .secondary)
            Toggle("AI", isOn: Binding(get: { state.aiEnabled }, set: { state.setAIEnabled($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .disabled(state.stopping)
        .help(state.aiEnabled
              ? "Turn AI off: stop running work and free the memory right away (⇧⌘K)"
              : "Turn AI on: Tidywise sorts again \(state.intervalText) (⇧⌘K)")
    }
}
