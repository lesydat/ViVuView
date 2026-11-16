import AppKit

/// Runs a UI script given with `--script <file>` (docs/TECH_SPEC.md §11.3).
/// One command per line; blank lines and lines starting with `#` are ignored; paths may be relative
/// to the current directory. Any failure prints `script error:` and exits with status 1.
@MainActor
final class ScriptRunner {
    private let scriptURL: URL
    private let viewer: ViewerController

    init(scriptURL: URL, viewer: ViewerController) {
        self.scriptURL = scriptURL
        self.viewer = viewer
    }

    func start() {
        Task { @MainActor in
            do {
                let text = try String(contentsOf: scriptURL, encoding: .utf8)
                let commands = try ScriptParser.parse(text)
                for (line, command) in commands {
                    do { try await run(command) } catch { throw ScriptError.failed(line, "\(error)") }
                }
            } catch {
                FileHandle.standardError.write(Data("script error: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    private func run(_ command: ScriptCommand) async throws {
        switch command {
        case .wait(let ms):
            try await Task.sleep(for: .milliseconds(ms))
        case .snapshot(let path):
            try await settle()
            guard let rep = viewer.snapshot(), let png = rep.representation(using: .png, properties: [:]) else {
                throw ScriptError.message("could not capture the window")
            }
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            print("snapshot: \(url.path)")
        case .quit:
            NSApp.terminate(nil)
        case .open(let path):
            viewer.open(URL(fileURLWithPath: path))
            await viewer.waitForLoad()
        case .expectLoaded:
            if let error = viewer.lastError { throw ScriptError.message("image failed: \(error)") }
            guard viewer.meta != nil else { throw ScriptError.message("no image loaded") }
        case .expectError:
            guard viewer.lastError != nil else { throw ScriptError.message("expected a load error") }
        case .key(let spec):
            try viewer.performScriptKey(spec)
            try await settle()
        case .print:
            print(viewer.scriptState())
        case .action(let name):
            try viewer.performScriptAction(name)
            try await settle()
        case .setting(let key, let value):
            try viewer.settings.set(key, value)
            try await Task.sleep(for: .milliseconds(30))
        case .snapshotTransition(let path):
            guard let overlay = viewer.fx.overlay, viewer.isTransitioning, let image = overlay.view.snapshotImage() else {
                throw ScriptError.message("no transition running")
            }
            let rep = NSBitmapImageRep(cgImage: image)
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("snapshot: \(path)")
        case .expect(let text):
            let state = viewer.scriptState()
            guard state.contains(text) else { throw ScriptError.message("expected \"\(text)\" in: \(state)") }
        }
    }

    /// Lets pending layout, decodes and renders finish.
    private func settle() async throws {
        await viewer.waitForLoad()
        try await Task.sleep(for: .milliseconds(60))
    }
}

enum ScriptCommand: Equatable {
    case wait(milliseconds: Int)
    case snapshot(path: String)
    case quit
    case open(path: String)
    case expectLoaded
    case expectError
    case key(String)
    case print
    case action(String)
    case expect(String)
    case setting(String, String)
    case snapshotTransition(String)
}

enum ScriptParser {
    static func parse(_ text: String) throws -> [(Int, ScriptCommand)] {
        var commands: [(Int, ScriptCommand)] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
            let command: ScriptCommand
            switch (parts[0], argument) {
            case ("wait", let value?):
                guard let ms = Int(value), ms >= 0 else { throw ScriptError.badLine(index + 1, line) }
                command = .wait(milliseconds: ms)
            case ("snapshot", let path?): command = .snapshot(path: path)
            case ("quit", nil): command = .quit
            case ("open", let path?): command = .open(path: path)
            case ("expect-loaded", nil): command = .expectLoaded
            case ("expect-error", nil): command = .expectError
            case ("key", let spec?): command = .key(spec)
            case ("print", nil): command = .print
            case ("action", let name?): command = .action(name)
            case ("expect", let text?): command = .expect(text)
            case ("snapshot-transition", let path?): command = .snapshotTransition(path)
            case ("setting", let rest?):
                let kv = rest.split(separator: " ", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { throw ScriptError.badLine(index + 1, line) }
                command = .setting(kv[0], kv[1])
            default: throw ScriptError.badLine(index + 1, line)
            }
            commands.append((index + 1, command))
        }
        return commands
    }
}

enum ScriptError: Error, CustomStringConvertible {
    case badLine(Int, String)
    case failed(Int, String)
    case message(String)

    var description: String {
        switch self {
        case .badLine(let number, let line): "line \(number): cannot understand \"\(line)\""
        case .failed(let number, let why): "line \(number): \(why)"
        case .message(let text): text
        }
    }
}
