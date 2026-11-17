import AppKit
import ViVuCore

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
        // Hover comes only from `action hover/unhover`: wherever the real pointer is must not change results.
        viewer.ignoresRealPointer = true
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
        case .makeFixture(let path, let size):
            // Large pictures are generated at run time instead of being committed.
            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch url.pathExtension.lowercased() {
                case "tif", "tiff":
                    try TIFFWriter.write(to: url, width: size.width, height: size.height, bigTIFF: false, overviews: 0) { _, y, lw, rgb in
                        FixtureContent.fillRow(y: y, x0: 0, count: lw, width: size.width, height: size.height, into: rgb)
                    }
                case "psb", "psd":
                    try PSBWriter.write(to: url, width: size.width, height: size.height, large: url.pathExtension == "psb",
                                        compression: .rle) { y, rgb in
                        FixtureContent.fillRow(y: y, x0: 0, count: size.width, width: size.width, height: size.height, into: rgb)
                    }
                default:
                    try ImageWriter.write(ImageWriter.pattern(size: size, seed: 5), to: url, type: url.pathExtension == "png" ? .png : .jpeg)
                }
            }
        case .snapshotWindow(let name, let path):
            try await settle()
            try await Task.sleep(for: .milliseconds(400))
            let target: NSWindow?
            switch name {
            case "info": target = viewer.infoPanelState.window
            case "settings": target = (NSApp.delegate as? AppDelegate)?.settingsController.window
            case "main": target = viewer.window
            case "shortcuts": target = ShortcutsPanel.shared.window
            default: throw ScriptError.message("unknown window \(name)")
            }
            // The frame view also draws the title bar, toolbar and traffic lights.
            guard let window = target, window.isVisible, let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw ScriptError.message("\(name) window not shown")
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            // Glass and blur do not render into bitmaps: put the picture on a dark backdrop.
            let out = NSImage(size: view.bounds.size)
            out.lockFocus()
            NSColor(white: 0.14, alpha: 1).setFill()
            view.bounds.fill()
            rep.draw(in: view.bounds)
            out.unlockFocus()
            guard let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ScriptError.message("capture") }
            try Self.write(cg, to: path)
        case .snapshotFilmstrip(let path):
            try await settle()
            try await Task.sleep(for: .milliseconds(300))
            guard let panel = viewer.strip.panel, panel.isVisible, let image = panel.stripView.snapshotImage() else {
                throw ScriptError.message("filmstrip not shown")
            }
            try Self.write(image, to: path)
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

    static func write(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        print("snapshot: \(path)")
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
    case snapshotFilmstrip(String)
    case makeFixture(String, PixelSize)
    case snapshotWindow(String, String)
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
            case ("snapshot-filmstrip", let path?): command = .snapshotFilmstrip(path)
            case ("snapshot-window", let rest?):
                let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { throw ScriptError.badLine(index + 1, line) }
                command = .snapshotWindow(parts[0], parts[1])
            case ("make-fixture", let rest?):
                let parts = rest.split(separator: " ").map(String.init)
                let dims = parts.last?.split(separator: "x").compactMap { Int($0) } ?? []
                guard parts.count == 2, dims.count == 2 else { throw ScriptError.badLine(index + 1, line) }
                command = .makeFixture(parts[0], PixelSize(width: dims[0], height: dims[1]))
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
