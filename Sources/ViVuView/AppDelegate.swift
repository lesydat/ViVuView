import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private var window: NSWindow?
    private var scriptRunner: ScriptRunner?

    init(arguments: [String]) {
        self.arguments = arguments
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = ViewerWindow.makeEmpty()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window

        if let scriptPath = Self.value(after: "--script", in: arguments) {
            let runner = ScriptRunner(scriptURL: URL(fileURLWithPath: scriptPath), window: window)
            scriptRunner = runner
            runner.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
