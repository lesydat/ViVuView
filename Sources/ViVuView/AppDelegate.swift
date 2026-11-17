import AppKit
import UniformTypeIdentifiers
import ViVuCore
import ViVuRender

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private(set) var viewer: ViewerController?
    private var scriptRunner: ScriptRunner?
    private var benchRunner: BenchRunner?
    private lazy var settingsWindow = SettingsWindowController(settings: Settings.shared)
    /// Files handed over before the window exists (Finder double-click at launch).
    private var pendingOpen: URL?

    init(arguments: [String]) {
        self.arguments = arguments
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let renderer: Renderer
        do {
            renderer = try Renderer()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Máy này không có GPU Metal")
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let viewer = ViewerController(renderer: renderer)
        self.viewer = viewer
        if arguments.contains(where: { $0.hasPrefix("--bench-") }) {
            let bench = BenchRunner(viewer: viewer)
            benchRunner = bench
            if let file = Self.value(after: "--bench-open", in: arguments) ?? Self.value(after: "--bench-idle", in: arguments)
                ?? Self.value(after: "--bench-zoom", in: arguments) {
                viewer.open(URL(fileURLWithPath: file))
            }
            viewer.show()
            NSApp.activate()
            Task { await bench.run(arguments: arguments) }
            return
        }
        if let url = pendingOpen ?? Self.fileArguments(arguments).first {
            viewer.open(url)
        }
        viewer.show()
        NSApp.activate()

        if let scriptPath = Self.value(after: "--script", in: arguments) {
            let runner = ScriptRunner(scriptURL: URL(fileURLWithPath: scriptPath), viewer: viewer)
            scriptRunner = runner
            runner.start()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let viewer { viewer.open(url) } else { pendingOpen = url }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Settings.shared.quitOnLastWindow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { viewer?.show() }
        return true
    }

    @objc func showSettings(_ sender: Any?) {
        settingsWindow.show()
    }

    func showSettings(tab: SettingsTab) {
        settingsWindow.show(tab: tab)
    }

    var settingsController: SettingsWindowController { settingsWindow }

    @objc func showShortcuts(_ sender: Any?) {
        ShortcutsPanel.shared.toggle(over: viewer?.window)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image] + FormatCatalog.extensions.compactMap { UTType(filenameExtension: $0) }
        if let url = viewer?.currentURL { panel.directoryURL = url.deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewer?.show()
        viewer?.open(url)
    }

    /// Paths on the command line that are not options (`--script x`, `--bench-… x`, `-NSFoo value`).
    static func fileArguments(_ arguments: [String]) -> [URL] {
        var urls: [URL] = []
        var skipNext = false
        for argument in arguments.dropFirst() {
            if skipNext { skipNext = false; continue }
            if argument.hasPrefix("-") { skipNext = true; continue }
            urls.append(URL(fileURLWithPath: argument))
        }
        return urls
    }

    static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
