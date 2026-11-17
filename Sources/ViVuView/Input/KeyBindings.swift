import AppKit

/// Everything the viewer can be asked to do from keys, menus, buttons, gestures and scripts.
enum Command: String, CaseIterable {
    case next, previous, first, last
    case zoomIn, zoomOut, actualSize, fit
    case panLeft, panRight, panUp, panDown
    case rotateLeft, rotateRight
    case toggleFullScreen, toggleFilmstrip, toggleGallery, toggleInfo, toggleStretch
    case previousFrame, nextFrame, togglePlayback
    case copyImage, copyPath, revealInFinder, moveToTrash
    case followImageSize
    case showShortcuts
    case escape
}

/// The one keyboard table (docs/UI_SPEC.md §6). Context decides between keys that mean different
/// things while zoomed (arrows pan) or on an animated image (Space pauses).
enum KeyBindings {
    struct Context {
        var isZoomed: Bool
        var isAnimated: Bool
        var inGallery: Bool
    }

    static func command(for event: NSEvent, context: Context) -> Command? {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let chars = event.charactersIgnoringModifiers ?? ""
        return command(key: Key(event: event), characters: chars, modifiers: mods, context: context)
    }

    enum Key: Equatable {
        case left, right, up, down, home, end, pageUp, pageDown, space, enter, escape, delete, other

        init(event: NSEvent) {
            switch Int(event.keyCode) {
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            case 115: self = .home
            case 119: self = .end
            case 116: self = .pageUp
            case 121: self = .pageDown
            case 49: self = .space
            case 36, 76: self = .enter
            case 53: self = .escape
            case 51, 117: self = .delete
            default: self = .other
            }
        }
    }

    static func command(key: Key, characters: String, modifiers: NSEvent.ModifierFlags, context: Context) -> Command? {
        let cmd = modifiers.contains(.command), shift = modifiers.contains(.shift)
        switch key {
        case .left: return cmd ? .previous : (context.isZoomed ? .panLeft : .previous)
        case .right: return cmd ? .next : (context.isZoomed ? .panRight : .next)
        // Only pan: zooming here clashed with panning once zoomed. Zoom is + − (⌘+ ⌘−), pinch or ⌘ + wheel.
        case .up: return context.isZoomed && !cmd ? .panUp : nil
        case .down: return context.isZoomed && !cmd ? .panDown : nil
        case .home: return .first
        case .end: return .last
        case .pageUp: return .previous
        case .pageDown: return .next
        case .space:
            if context.isAnimated && !shift { return .togglePlayback }
            return shift ? .previous : .next
        case .enter: return .toggleGallery
        case .escape: return .escape
        case .delete: return cmd ? .moveToTrash : nil
        case .other: break
        }
        if cmd {
            switch characters.lowercased() {
            case "c": return shift ? .copyPath : .copyImage
            case "r": return shift ? .revealInFinder : nil
            default: return nil
            }
        }
        switch characters {
        case "+", "=": return .zoomIn
        case "-", "_": return .zoomOut
        case "0": return .actualSize
        case "\\": return .fit
        case "[": return .rotateLeft
        case "]": return .rotateRight
        case "f", "F": return .toggleFullScreen
        case "t", "T": return .toggleFilmstrip
        case "g", "G": return .toggleGallery
        case "i", "I": return .toggleInfo
        case "e", "E": return .toggleStretch
        case ",": return .previousFrame
        case ".": return .nextFrame
        case "?": return .showShortcuts
        default: return nil
        }
    }

    /// Parses script key specs like "right", "cmd+right", "0", "\\", "[", "shift+space".
    static func parse(_ spec: String) -> (Key, String, NSEvent.ModifierFlags)? {
        var mods: NSEvent.ModifierFlags = []
        var parts = spec.lowercased().split(separator: "+").map(String.init)
        if spec.hasSuffix("+") { parts = Array(parts) + ["+"] }   // "cmd++" or "+"
        guard let last = parts.popLast() else { return nil }
        for p in parts {
            switch p {
            case "cmd": mods.insert(.command)
            case "shift": mods.insert(.shift)
            case "alt", "opt": mods.insert(.option)
            case "ctrl": mods.insert(.control)
            default: return nil
            }
        }
        let named: [String: Key] = ["left": .left, "right": .right, "up": .up, "down": .down, "home": .home, "end": .end,
                                    "pageup": .pageUp, "pagedown": .pageDown, "space": .space, "enter": .enter,
                                    "escape": .escape, "esc": .escape, "delete": .delete]
        if let key = named[last] { return (key, "", mods) }
        let char = last == "backslash" ? "\\" : last
        return (.other, char, mods)
    }
}
