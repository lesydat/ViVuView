import AppKit
import SwiftUI

/// Every way to reach each command: keys found by asking `KeyBindings` about every key (so the sheet cannot drift
/// from the real table), the menu's ⌘ shortcuts, and the gestures of docs/UI_SPEC.md §5 (docs/UI_SPEC.md §6.1).
@MainActor
enum ShortcutTable {
    struct Entry: Hashable {
        /// Key combination drawn as a keycap, or a gesture drawn as plain text.
        let label: String
        var isGesture = false
        /// When it applies ("khi đang zoom"); nil = always.
        var note: String?
    }

    struct Row: Identifiable {
        let id: String
        let title: String
        let entries: [Entry]
        /// The note every key of the row shares, shown once under the title.
        var sharedNote: String? {
            let notes = Set(entries.filter { !$0.isGesture }.map(\.note))
            return notes.count == 1 ? notes.first ?? nil : nil
        }
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    static func groups() -> [Group] {
        let keys = probedKeys()
        func row(_ command: Command, gestures: [String] = []) -> Row {
            var entries = keys[command] ?? []
            let menu = MenuCommand.of(command)
            if !menu.key.isEmpty, !menu.modifiers.intersection([.command, .control, .option]).isEmpty {
                let label = symbols(menu.modifiers) + keyName(menu.key)
                if !entries.contains(where: { $0.label == label }) { entries.append(Entry(label: label)) }
            }
            entries += gestures.map { Entry(label: $0, isGesture: true) }
            return Row(id: command.rawValue, title: menu.title, entries: entries)
        }
        func fixed(_ id: String, _ title: String, _ labels: [String], gestures: [String] = []) -> Row {
            Row(id: id, title: title, entries: labels.map { Entry(label: $0) } + gestures.map { Entry(label: $0, isGesture: true) })
        }
        let pan = [Command.panLeft, .panRight, .panUp, .panDown].flatMap { keys[$0] ?? [] }
        let swipe = String(localized: "vuốt 2 ngón ngang")
        let wheel = String(localized: "⌘ + lăn chuột")
        return [
            Group(id: "browse", title: String(localized: "Chuyển ảnh"), rows: [
                row(.next, gestures: [swipe]), row(.previous, gestures: [swipe]), row(.first), row(.last),
            ]),
            Group(id: "zoom", title: String(localized: "Zoom và di chuyển"), rows: [
                row(.zoomIn, gestures: [String(localized: "mở 2 ngón"), wheel]),
                row(.zoomOut, gestures: [String(localized: "chụm 2 ngón"), wheel]), row(.actualSize), row(.fit),
                fixed("toggleZoom", String(localized: "Vừa cửa sổ ↔ 100%"), [],
                      gestures: [String(localized: "nhấn đúp"), String(localized: "chạm đúp 2 ngón")]),
                Row(id: "pan", title: MenuCommand.of(.panLeft).title, entries: pan + [
                    Entry(label: String(localized: "kéo chuột"), isGesture: true),
                    Entry(label: String(localized: "cuộn 2 ngón"), isGesture: true),
                    Entry(label: String(localized: "lăn chuột"), isGesture: true),
                ]),
            ]),
            Group(id: "turn", title: String(localized: "Xoay và hiển thị"), rows: [
                row(.rotateLeft), row(.rotateRight),
                fixed("rotateFree", String(localized: "Xoay theo tay"), [], gestures: [String(localized: "xoay 2 ngón")]),
                row(.toggleStretch),
            ]),
            Group(id: "animation", title: String(localized: "Ảnh động"), rows: [
                row(.togglePlayback), row(.previousFrame), row(.nextFrame),
            ]),
            Group(id: "window", title: String(localized: "Cửa sổ"), rows: [
                row(.toggleInfo),
                row(.toggleFilmstrip, gestures: [String(localized: "vuốt 2 ngón lên / xuống")]),
                row(.toggleGallery, gestures: [String(localized: "chụm 2 ngón quá vừa cửa sổ")]),
                row(.toggleFullScreen), row(.escape),
            ]),
            Group(id: "file", title: String(localized: "Tệp"), rows: [
                fixed("open", String(localized: "Mở…"), ["⌘O"]),
                row(.copyImage), row(.copyPath), row(.revealInFinder), row(.moveToTrash),
                fixed("close", String(localized: "Đóng"), ["⌘W"]),
                fixed("settings", String(localized: "Cài đặt…"), ["⌘,"]),
                row(.showShortcuts),
                fixed("quit", String(localized: "Thoát ViVuView"), ["⌘Q"]),
            ]),
            // The gallery reads keys itself (ViewerController+Gallery `galleryKey`).
            Group(id: "gallery", title: "Gallery", rows: [
                fixed("gNeighbour", String(localized: "Ô trước / sau"), ["←", "→"]),
                fixed("gColumn", String(localized: "Ô trên / dưới cùng cột"), ["↑", "↓"]),
                fixed("gPage", String(localized: "Trang trước / sau"), ["Page Up", "Page Down"]),
                fixed("gEnds", String(localized: "Ô đầu / cuối"), ["Home", "End"]),
                fixed("gOpen", String(localized: "Mở ảnh"), ["Enter", "Space"], gestures: [String(localized: "click")]),
                fixed("gBack", String(localized: "Quay lại ảnh đang xem"), ["Esc", "G"]),
                fixed("gSize", String(localized: "Đổi cỡ ô"), ["⌘+", "⌘−"], gestures: [String(localized: "chụm / mở 2 ngón")]),
                fixed("gType", String(localized: "Nhảy tới file theo tên"), ["A…Z"]),
            ]),
        ]
    }

    /// Asks KeyBindings about every key with each modifier set, still and zoomed and animated, and notes the
    /// situations a key only works in.
    static func probedKeys() -> [Command: [Entry]] {
        typealias Context = KeyBindings.Context
        let situations: [(Context, String)] = [
            (Context(isZoomed: false, isAnimated: false, inGallery: false), "still"),
            (Context(isZoomed: true, isAnimated: false, inGallery: false), "zoomed"),
            (Context(isZoomed: false, isAnimated: true, inGallery: false), "animated"),
        ]
        let named: [(KeyBindings.Key, String)] = [
            (.left, "←"), (.right, "→"), (.up, "↑"), (.down, "↓"), (.space, "Space"), (.pageUp, "Page Up"),
            (.pageDown, "Page Down"), (.home, "Home"), (.end, "End"), (.enter, "Enter"), (.escape, "Esc"), (.delete, "⌫"),
        ]
        // "=" and "_" share keys with "+" and "−"; letters are probed lowercase and shown uppercase.
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789+-[]\\,./;'`?").map(String.init)
        let modifierSets: [NSEvent.ModifierFlags] = [[], .shift, .command, [.command, .shift]]
        var inputs: [(KeyBindings.Key, String, NSEvent.ModifierFlags, String)] = []
        for mods in modifierSets {
            for (key, name) in named { inputs.append((key, "", mods, symbols(mods) + name)) }
            for char in characters where mods.contains(.command) || !mods.contains(.shift) {
                inputs.append((.other, char, mods, symbols(mods) + keyName(char)))
            }
        }
        func commands(_ key: KeyBindings.Key, _ chars: String, _ mods: NSEvent.ModifierFlags) -> [Command?] {
            situations.map { KeyBindings.command(key: key, characters: chars, modifiers: mods, context: $0.0) }
        }
        var result: [Command: [Entry]] = [:]
        for (key, chars, mods, label) in inputs {
            let mapped = commands(key, chars, mods)
            // KeyBindings ignores modifiers it does not use (⇧→ is →): list a combination only when it does
            // something other than the same key with any one modifier fewer.
            let parents = [NSEvent.ModifierFlags.shift, .command].filter { mods.contains($0) }.map { mods.subtracting($0) }
            if parents.contains(where: { commands(key, chars, $0) == mapped }) { continue }
            var found: [Command: Set<String>] = [:]
            for ((_, name), command) in zip(situations, mapped) {
                if let command { found[command, default: []].insert(name) }
            }
            for (command, where_) in found {
                let entry = Entry(label: label, note: note(for: where_))
                if !(result[command] ?? []).contains(entry) { result[command, default: []].append(entry) }
            }
        }
        // Plain keys first, then shifted, then ⌘.
        return result.mapValues { $0.enumerated().sorted { rank($0.element) == rank($1.element) ? $0.offset < $1.offset
                                                                                             : rank($0.element) < rank($1.element) }
                                                 .map(\.element) }
    }

    private static func rank(_ entry: Entry) -> Int {
        entry.label.hasPrefix("⌘") || entry.label.hasPrefix("⌃") ? 2 : entry.label.hasPrefix("⇧") ? 1 : 0
    }

    private static func note(for situations: Set<String>) -> String? {
        switch situations {
        case ["still", "zoomed", "animated"]: nil
        case ["still", "animated"]: String(localized: "khi chưa zoom")
        case ["zoomed"]: String(localized: "khi đang zoom")
        case ["animated"]: String(localized: "ảnh động")
        case ["still", "zoomed"]: String(localized: "ảnh tĩnh")
        default: nil
        }
    }

    static func symbols(_ mods: NSEvent.ModifierFlags) -> String {
        (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "") + (mods.contains(.shift) ? "⇧" : "")
            + (mods.contains(.command) ? "⌘" : "")
    }

    static func keyName(_ key: String) -> String {
        switch key {
        case String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!): "→"
        case String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!): "←"
        case String(UnicodeScalar(UInt16(NSHomeFunctionKey))!): "Home"
        case String(UnicodeScalar(UInt16(NSEndFunctionKey))!): "End"
        case String(UnicodeScalar(UInt16(NSBackspaceCharacter))!): "⌫"
        case " ": "Space"
        case "-": "−"
        default: key.uppercased()
        }
    }

    /// Plain text of the sheet (scripts).
    static func text() -> String {
        groups().map { group in
            "[\(group.title)]\n" + group.rows.map { row in
                "  \(row.title): " + row.entries.map { $0.label + ($0.note.map { " (\($0))" } ?? "") }.joined(separator: " · ")
            }.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

/// The shortcut sheet (⌘/ or ?): a glass panel over the viewer window, closed by Esc, ⌘/, ? or clicking elsewhere.
@MainActor
final class ShortcutsPanel: NSObject, NSWindowDelegate {
    static let shared = ShortcutsPanel()

    private(set) var window: NSPanel?

    var isShown: Bool { window?.isVisible == true }

    func toggle(over parent: NSWindow?) {
        if isShown { close() } else { show(over: parent) }
    }

    func show(over parent: NSWindow?) {
        close()
        let anchor = parent ?? NSApp.keyWindow ?? NSApp.mainWindow
        let screen = anchor?.screen ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let natural = NSHostingView(rootView: ShortcutsView(scrolls: false)).fittingSize
        let size = NSSize(width: min(natural.width, area.width - 40), height: min(natural.height, area.height - 40))
        let scrolls = size.height < natural.height || size.width < natural.width
        let hosting = NSHostingView(rootView: ShortcutsView(scrolls: scrolls))
        hosting.appearance = NSAppearance(named: .darkAqua)
        let background = OverlayBackground.make(content: hosting, cornerRadius: Self.cornerRadius, behindWindow: true)

        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.contentView = background
        panel.delegate = self
        panel.onClose = { [weak self] in self?.close() }
        let center = anchor.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSPoint(x: area.midX, y: area.midY)
        var origin = NSPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded())
        origin.x = min(max(origin.x, area.minX + 20), area.maxX - size.width - 20)
        origin.y = min(max(origin.y, area.minY + 20), area.maxY - size.height - 20)
        panel.setFrameOrigin(origin)
        // A child of the viewer moves and goes full screen with it.
        if let parent, parent.isVisible { parent.addChildWindow(panel, ordered: .above) }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        window = panel
    }

    func close() {
        guard let panel = window else { return }
        window = nil
        panel.delegate = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else closes it, like a popover.
        close()
    }

    static let cornerRadius: CGFloat = 20
}

/// Borderless panels cannot become key by default; this one must, for Esc and ?.
private final class KeyPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.keyCode == 53 || chars == "?" { onClose?(); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }
}

struct ShortcutsView: View {
    let scrolls: Bool

    private static let columnWidth: CGFloat = 420

    var body: some View {
        if scrolls {
            ScrollView { content }
        } else {
            content
        }
    }

    private var content: some View {
        let groups = ShortcutTable.groups()
        let split = 4   // browse, zoom, turn, animation | window, file, gallery
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Phím tắt")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(String(localized: "Esc hoặc ⌘/ để đóng")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 28) {
                column(Array(groups.prefix(split)))
                column(Array(groups.dropFirst(split)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.4))
        .foregroundStyle(.primary)
    }

    private func column(_ groups: [ShortcutTable.Group]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title.uppercased())
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(group.rows) { row in rowView(row) }
                }
            }
        }
        .frame(width: Self.columnWidth, alignment: .leading)
    }

    private func rowView(_ row: ShortcutTable.Row) -> some View {
        let shared = row.sharedNote
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let shared {
                    Text(shared).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, alignment: .leading)
            FlowLayout(spacing: 5, lineSpacing: 4) {
                ForEach(row.entries, id: \.self) { entry in
                    entryView(entry, showNote: shared == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func entryView(_ entry: ShortcutTable.Entry, showNote: Bool) -> some View {
        if entry.isGesture {
            // Gestures: plain text after a hand, so they do not read as notes.
            HStack(spacing: 3) {
                Image(systemName: "hand.point.up.left").font(.system(size: 10))
                Text(entry.label).font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                Text(verbatim: entry.label)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .frame(minWidth: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                if showNote, let note = entry.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Lays children left to right, wrapping to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let used = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if needed > width, !line.items.isEmpty {
                lines.append(line)
                line = Line()
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append(index)
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
