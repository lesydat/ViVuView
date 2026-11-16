import AppKit

/// Runs a UI script given with `--script <file>` (docs/TECH_SPEC.md §11.3).
/// One command per line; blank lines and lines starting with `#` are ignored.
/// Commands available so far: `wait <ms>`, `snapshot <path.png>`, `quit`.
/// Later milestones add open, next, prev, zoom, fit, rotate, gallery, filmstrip, info, settings.
@MainActor
final class ScriptRunner {
    enum Command: Equatable {
        case wait(milliseconds: Int)
        case snapshot(path: String)
        case quit
    }

    private let scriptURL: URL
    private weak var window: NSWindow?

    init(scriptURL: URL, window: NSWindow) {
        self.scriptURL = scriptURL
        self.window = window
    }

    func start() {
        Task { @MainActor in
            do {
                let text = try String(contentsOf: scriptURL, encoding: .utf8)
                let commands = try Self.parse(text)
                for command in commands {
                    try await run(command)
                }
                // A script that does not end with `quit` leaves the app running.
            } catch {
                Self.fail("\(error)")
            }
        }
    }

    static func parse(_ text: String) throws -> [Command] {
        var commands: [Command] = []
        for (number, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
            switch (parts[0], argument) {
            case ("wait", let value?):
                guard let ms = Int(value), ms >= 0 else { throw ScriptError.badLine(number + 1, line) }
                commands.append(.wait(milliseconds: ms))
            case ("snapshot", let path?):
                commands.append(.snapshot(path: path))
            case ("quit", nil):
                commands.append(.quit)
            default:
                throw ScriptError.badLine(number + 1, line)
            }
        }
        return commands
    }

    private func run(_ command: Command) async throws {
        switch command {
        case .wait(let ms):
            try await Task.sleep(for: .milliseconds(ms))
        case .snapshot(let path):
            try snapshot(to: URL(fileURLWithPath: path))
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// Writes the window's content view to a PNG.
    private func snapshot(to url: URL) throws {
        guard let view = window?.contentView else { throw ScriptError.noWindow }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw ScriptError.snapshotFailed }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw ScriptError.snapshotFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        print("snapshot: \(url.path)")
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("script error: \(message)\n".utf8))
        exit(1)
    }
}

enum ScriptError: Error, CustomStringConvertible {
    case badLine(Int, String)
    case noWindow
    case snapshotFailed

    var description: String {
        switch self {
        case .badLine(let number, let line): "line \(number): cannot understand \"\(line)\""
        case .noWindow: "no window to snapshot"
        case .snapshotFailed: "could not capture the window"
        }
    }
}
